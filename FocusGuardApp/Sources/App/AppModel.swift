import Foundation
import Observation
import SharedCore

enum AppModelError: LocalizedError {
    case emptyGoal
    case invalidDuration
    case sessionAlreadyActive
    case missingProvider
    case activeSessionBlocksArchive

    var errorDescription: String? {
        switch self {
        case .emptyGoal: String(localized: "请先写下这次要完成的目标。")
        case .invalidDuration: String(localized: "专注时长必须在 1 分钟到 23 小时 59 分钟之间。")
        case .sessionAlreadyActive: String(localized: "已有一场专注正在进行。")
        case .missingProvider: String(localized: "开始专注前，请先在设置中保存 AI Provider 和 API Key。")
        case .activeSessionBlocksArchive: String(localized: "请先结束当前专注，再导入或导出数据。")
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var sessions: [FocusSession] = []
    var activeSession: FocusSession?
    var reminderPreferences = ReminderPreferencesStore.load()
    var durationPreferences = DurationPreferencesStore.load()
    var analysisPreferences = AnalysisPreferencesStore.load()
    var isBusy = false
    var errorMessage: String?

    let providerStore = ProviderStore()

    private let repository = SessionRepository()
    private let eventStore = SharedEventStore()
    private let notifications = NotificationService.shared
    private let liveActivity = LiveActivityController()
    @ObservationIgnored
    private lazy var backupCoordinator = BackupCoordinator(repository: repository, providerStore: providerStore)

    func bootstrap() async {
        isBusy = true
        defer { isBusy = false }
        _ = try? await notifications.requestAuthorization()
        _ = try? ThumbnailStore.removeExpired()
        do {
            sessions = try await repository.loadSessions()
            try await importPendingEvents()
            if let context = try await repository.loadActive() {
                var session: FocusSession
                if let existing = sessions.first(where: { $0.id == context.sessionID }) {
                    session = existing
                } else {
                    session = FocusSession(
                        id: context.sessionID,
                        goal: context.goal,
                        plannedStart: context.startedAt,
                        plannedEnd: context.endsAt,
                        mode: context.mode
                    )
                    try await repository.upsert(session)
                    replaceSession(session)
                }
                if session.status != .active || session.actualEnd != nil {
                    session.status = .active
                    session.actualEnd = nil
                    try await repository.upsert(session)
                    replaceSession(session)
                }
                activeSession = session
                if Date() >= context.endsAt {
                    await finishSession(status: .completed, endDate: context.endsAt)
                }
            } else {
                await finishOrphanedActiveSessions()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveReminderPreferences() {
        do {
            try ReminderPreferencesStore.save(reminderPreferences)
            var dates = PreferenceModificationDatesStore.load()
            dates.reminders = .now
            try PreferenceModificationDatesStore.save(dates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveQuickDuration(at index: Int, minutes: Int) {
        guard durationPreferences.quickMinutes.indices.contains(index),
              DurationPreferences.allowedMinutes.contains(minutes) else {
            errorMessage = AppModelError.invalidDuration.localizedDescription
            return
        }
        do {
            durationPreferences.quickMinutes[index] = minutes
            try DurationPreferencesStore.save(durationPreferences)
            var dates = PreferenceModificationDatesStore.load()
            dates.quickDurations = .now
            try PreferenceModificationDatesStore.save(dates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAnalysisPreferences() {
        do {
            analysisPreferences = AnalysisPreferences(
                sampleIntervalSeconds: analysisPreferences.sampleIntervalSeconds
            )
            try AnalysisPreferencesStore.save(analysisPreferences)
            var dates = PreferenceModificationDatesStore.load()
            dates.analysis = .now
            try PreferenceModificationDatesStore.save(dates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rewriteGoal(_ goal: String) async -> GoalRewriteResult? {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = AppModelError.emptyGoal.localizedDescription
            return nil
        }
        guard let service = providerStore.makeService() else {
            errorMessage = AppModelError.missingProvider.localizedDescription
            return nil
        }
        isBusy = true
        defer { isBusy = false }
        do {
            return try await service.rewriteGoal(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func startSession(goal rawGoal: String, durationMinutes: Int) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let goal = rawGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty else { throw AppModelError.emptyGoal }
            guard DurationPreferences.allowedMinutes.contains(durationMinutes) else {
                throw AppModelError.invalidDuration
            }
            guard activeSession == nil else { throw AppModelError.sessionAlreadyActive }
            guard providerStore.hasAPIKey else { throw AppModelError.missingProvider }

            let start = Date()
            let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            let session = FocusSession(
                goal: goal,
                plannedStart: start,
                plannedEnd: end,
                mode: .broadcastAI
            )
            let context = ActiveSessionContext(
                sessionID: session.id,
                goal: goal,
                startedAt: start,
                endsAt: end,
                mode: .broadcastAI,
                provider: providerStore.configuration,
                reminderPreferences: reminderPreferences,
                analysisPreferences: analysisPreferences
            )

            try await repository.saveActive(context)
            do {
                try await repository.upsert(session)
            } catch {
                try? await repository.clearActive()
                throw error
            }
            await notifications.scheduleSessionEnd(sessionID: session.id, goal: goal, at: end)
            liveActivity.start(session: session)
            sessions.insert(session, at: 0)
            activeSession = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopSession() async {
        await finishSession(status: .cancelled, endDate: Date())
    }

    func refreshActiveSession() async {
        guard let activeSession else { return }
        if Date() >= activeSession.plannedEnd {
            await finishSession(status: .completed, endDate: activeSession.plannedEnd)
        } else {
            await importPendingEventsForActiveSession()
        }
    }

    func deleteAllHistory() async {
        guard activeSession == nil else {
            errorMessage = String(localized: "请先结束当前专注，再删除历史。")
            return
        }
        do {
            try await repository.deleteAll()
            await eventStore.deleteAll()
            let container = SharedEnvironment.containerURL()
            let thumbnails = container.appendingPathComponent("thumbnails")
            let events = container.appendingPathComponent("events")
            try? FileManager.default.removeItem(at: thumbnails)
            try? FileManager.default.removeItem(at: events)
            sessions = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSession(id: UUID) async {
        guard activeSession?.id != id else {
            errorMessage = String(localized: "进行中的专注不能删除。")
            return
        }
        do {
            try await repository.delete(sessionID: id)
            try await eventStore.delete(sessionID: id)
            ThumbnailStore.deleteSession(id)
            sessions.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func session(with id: UUID) -> FocusSession? {
        sessions.first { $0.id == id }
    }

    func exportArchive() async -> URL? {
        guard activeSession == nil else {
            errorMessage = AppModelError.activeSessionBlocksArchive.localizedDescription
            return nil
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await importPendingEvents()
            return try await backupCoordinator.exportArchive()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func previewImport(url: URL) async -> ImportPreview? {
        guard activeSession == nil else {
            errorMessage = AppModelError.activeSessionBlocksArchive.localizedDescription
            return nil
        }
        isBusy = true
        defer { isBusy = false }
        do {
            return try await backupCoordinator.previewImport(url: url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyImport(_ preview: ImportPreview) async -> Bool {
        guard activeSession == nil else {
            errorMessage = AppModelError.activeSessionBlocksArchive.localizedDescription
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            sessions = try await backupCoordinator.applyImport(preview)
            reminderPreferences = ReminderPreferencesStore.load()
            durationPreferences = DurationPreferencesStore.load()
            analysisPreferences = AnalysisPreferencesStore.load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func discardPendingImport() {
        backupCoordinator.discardPendingImport()
    }

    func removeTemporaryArchive(at url: URL?) {
        backupCoordinator.removeTemporaryArchive(at: url)
    }

    private func finishSession(status: SessionStatus, endDate: Date) async {
        guard var session = activeSession else { return }
        isBusy = true
        try? await repository.clearActive()
        await notifications.cancelSessionEnd(sessionID: session.id)
        await liveActivity.end(sessionID: session.id)

        let imported = (try? await eventStore.drain(sessionID: session.id)) ?? []
        session.events = merged(session.events, imported)
        session.actualEnd = endDate
        session.status = status
        session.breakdown = SessionMetrics.breakdown(
            events: session.events,
            from: session.plannedStart,
            to: endDate
        )
        if let service = providerStore.makeService() {
            session.summary = try? await service.summarizeSession(.init(session: session))
        }
        if session.summary == nil {
            session.summary = deterministicSummary(for: session)
        }
        session.modifiedAt = .now
        try? await repository.upsert(session)
        activeSession = nil
        replaceSession(session)
        isBusy = false
    }

    private func importPendingEvents() async throws {
        for var session in sessions {
            let pending = try await eventStore.drain(sessionID: session.id)
            guard !pending.isEmpty else { continue }
            session.events = merged(session.events, pending)
            if session.status != .active {
                session.breakdown = SessionMetrics.breakdown(
                    events: session.events,
                    from: session.plannedStart,
                    to: session.effectiveEnd
                )
            }
            session.modifiedAt = .now
            try await repository.upsert(session)
            replaceSession(session)
        }
    }

    private func finishOrphanedActiveSessions() async {
        let orphans = sessions.filter { $0.status == .active }
        for orphan in orphans {
            activeSession = orphan
            let now = Date()
            let completed = now >= orphan.plannedEnd
            await finishSession(
                status: completed ? .completed : .cancelled,
                endDate: completed ? orphan.plannedEnd : now
            )
        }
    }

    private func importPendingEventsForActiveSession() async {
        guard var session = activeSession else { return }
        let pending = (try? await eventStore.drain(sessionID: session.id)) ?? []
        guard !pending.isEmpty else { return }
        session.events = merged(session.events, pending)
        session.modifiedAt = .now
        activeSession = session
        replaceSession(session)
        try? await repository.upsert(session)
    }

    private func merged(_ existing: [FocusEvent], _ incoming: [FocusEvent]) -> [FocusEvent] {
        var values: [UUID: FocusEvent] = [:]
        for event in existing + incoming {
            values[event.id] = event
        }
        return values.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func replaceSession(_ session: FocusSession) {
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        sessions.sort { $0.plannedStart > $1.plannedStart }
    }

    private func deterministicSummary(for session: FocusSession) -> String {
        let coverage = Int((session.breakdown.coverage * 100).rounded())
        return String(localized: "本次记录覆盖了 \(coverage)% 的会话时间。专注 \(Int(session.breakdown.focusedSeconds / 60)) 分钟，走神 \(Int(session.breakdown.wanderingSeconds / 60)) 分钟，分心 \(Int(session.breakdown.distractedSeconds / 60)) 分钟。未观测部分不会计入专注时间。")
    }
}
