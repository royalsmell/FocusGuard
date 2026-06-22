import Foundation
import XCTest
@testable import SharedCore

final class SharedStoresTests: XCTestCase {
    func testEventStoreWritesAndDrainsOnlyRequestedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedEventStore(containerURL: root)
        let firstID = UUID()
        let secondID = UUID()
        try await store.record(FocusEvent(sessionID: firstID, source: .visionAI, level: .focused))
        try await store.record(FocusEvent(sessionID: secondID, source: .visionAI, level: .distracted))

        let first = try await store.drain(sessionID: firstID)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.level, .focused)
        let second = try await store.drain(sessionID: secondID)
        XCTAssertEqual(second.count, 1)
    }

    func testSessionRepositoryRoundTripsActiveAndHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = SessionRepository(containerURL: root)
        let session = FocusSession(
            goal: "完成设计稿",
            plannedEnd: .now.addingTimeInterval(1_500),
            mode: .broadcastAI
        )
        try await repository.upsert(session)
        let loaded = try await repository.loadSessions()
        XCTAssertEqual(loaded.first?.id, session.id)

        let context = ActiveSessionContext(
            sessionID: session.id,
            goal: session.goal,
            startedAt: session.plannedStart,
            endsAt: session.plannedEnd,
            mode: session.mode,
            provider: .suggested
        )
        try await repository.saveActive(context)
        let active = try await repository.loadActive()
        XCTAssertEqual(active?.sessionID, context.sessionID)
        XCTAssertEqual(active?.goal, context.goal)
        XCTAssertEqual(active?.mode, context.mode)
        XCTAssertEqual(active?.provider, context.provider)
        XCTAssertEqual(
            active?.startedAt.timeIntervalSince1970 ?? 0,
            context.startedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            active?.endsAt.timeIntervalSince1970 ?? 0,
            context.endsAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        try await repository.clearActive()
        let cleared = try await repository.loadActive()
        XCTAssertNil(cleared)
    }

    func testRetentionRemovesOnlyExpiredFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldData = Data([1, 2, 3])
        let path = try ThumbnailStore.write(jpegData: oldData, sessionID: UUID(), containerURL: root)
        let url = root.appendingPathComponent(path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: url.path
        )
        let removed = try ThumbnailStore.removeExpired(olderThan: 30, now: Date(), containerURL: root)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testReminderPreferencesRoundTrip() throws {
        let suite = "FocusGuardTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReminderPreferences(
            silentWanderingEnabled: false,
            audibleDistractionEnabled: true
        )
        try ReminderPreferencesStore.save(preferences, defaults: defaults)
        XCTAssertEqual(ReminderPreferencesStore.load(defaults: defaults), preferences)
    }

    func testDurationPreferencesValidateAndRoundTrip() throws {
        let suite = "FocusGuardTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = DurationPreferences(quickMinutes: [5, 20, 40, 90, 120])
        try DurationPreferencesStore.save(preferences, defaults: defaults)
        XCTAssertEqual(DurationPreferencesStore.load(defaults: defaults), preferences)
        XCTAssertEqual(
            DurationPreferences(quickMinutes: [0, 20]).quickMinutes,
            DurationPreferences.defaultQuickMinutes
        )
    }

    func testFocusDurationConvertsHoursAndMinutes() {
        XCTAssertEqual(FocusDuration.totalMinutes(hours: 2, minutes: 15), 135)
        XCTAssertEqual(
            FocusDuration.components(totalMinutes: 135),
            FocusDurationComponents(hours: 2, minutes: 15)
        )
        XCTAssertEqual(
            FocusDuration.components(totalMinutes: 5_000),
            FocusDurationComponents(hours: 23, minutes: 59)
        )
    }

    func testSingleSessionDeletionPreservesOtherHistoryAndRemovesAssets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = SessionRepository(containerURL: root)
        let eventStore = SharedEventStore(containerURL: root)
        let first = FocusSession(goal: "第一项", plannedEnd: .now, mode: .broadcastAI, status: .completed)
        let second = FocusSession(goal: "第二项", plannedEnd: .now, mode: .broadcastAI, status: .completed)
        try await repository.upsert(first)
        try await repository.upsert(second)
        try await eventStore.record(FocusEvent(sessionID: first.id, source: .visionAI, level: .focused))
        let thumbnailPath = try ThumbnailStore.write(
            jpegData: Data([1]),
            sessionID: first.id,
            containerURL: root
        )

        try await repository.delete(sessionID: first.id)
        try await eventStore.delete(sessionID: first.id)
        ThumbnailStore.deleteSession(first.id, containerURL: root)

        let remainingSessions = try await repository.loadSessions()
        let remainingEvents = try await eventStore.drain(sessionID: first.id)
        XCTAssertEqual(remainingSessions.map(\.id), [second.id])
        XCTAssertTrue(remainingEvents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(thumbnailPath).path))
    }
}
