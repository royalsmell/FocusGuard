import CoreMedia
import Foundation
import ImageIO
import ReplayKit
import SharedCore
import UniformTypeIdentifiers
import UserNotifications

final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private let repository = SessionRepository()
    private let eventStore = SharedEventStore()
    private let imageProcessor = BroadcastImageProcessor()
    private let lock = NSLock()

    private var activeContext: ActiveSessionContext?
    private var lastSampleAt: Date?
    private var lastAnalyzedAt: Date?
    private var lastHash: UInt64?
    private var recentLevels: [FocusLevel] = []
    private var interventionEngine = InterventionEngine()
    private var isAnalyzing = false
    private var didNotifyConfigurationError = false
    private var isFinishingBroadcast = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        Task { [weak self] in
            guard let self else { return }
            guard let active = await loadActiveContextWithRetry() else {
                notify(
                    title: String(localized: "AI 守望未连接"),
                    body: String(localized: "请先在专注守望中开始一场 AI 广播会话，再开启系统屏幕广播。"),
                    sound: false
                )
                finishBroadcast(reason: String(localized: "没有可用的专注会话，屏幕广播已停止。"))
                return
            }
            lock.withLock { activeContext = active }
            try? await eventStore.record(
                FocusEvent(
                    sessionID: active.sessionID,
                    source: .broadcast,
                    level: .unknown,
                    reason: String(localized: "AI 屏幕广播已开始。"),
                    broadcastState: .started
                )
            )
        }
    }

    private func loadActiveContextWithRetry() async -> ActiveSessionContext? {
        for attempt in 0..<10 {
            if let active = try? await repository.loadActive(), Date() < active.endsAt {
                return active
            }
            if attempt < 9 {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        return nil
    }

    override func broadcastPaused() {
        recordBroadcastState(.paused, reason: String(localized: "AI 屏幕广播已暂停。"))
    }

    override func broadcastResumed() {
        recordBroadcastState(.resumed, reason: String(localized: "AI 屏幕广播已恢复。"))
    }

    override func broadcastFinished() {
        let automatic = lock.withLock { () -> Bool in
            let value = isFinishingBroadcast
            isFinishingBroadcast = true
            return value
        }
        if !automatic {
            recordBroadcastState(.stopped, reason: String(localized: "AI 屏幕广播已停止。"))
            notify(
                title: String(localized: "AI 守望已停止"),
                body: String(localized: "后续时间会记为未观测。"),
                sound: false
            )
        }
        lock.withLock { activeContext = nil }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Date()

        guard let lifecycleContext = lock.withLock({ activeContext }) else { return }
        if BroadcastLifecycle.shouldFinish(
            active: lifecycleContext,
            authoritative: ActiveSessionSnapshot.load(),
            now: now
        ) {
            finishBroadcast(reason: String(localized: "专注会话已结束，屏幕广播已自动停止。"))
            return
        }

        let snapshot: ActiveSessionContext? = lock.withLock {
            guard let activeContext,
                  !isAnalyzing,
                  now.timeIntervalSince(lastSampleAt ?? .distantPast)
                    >= TimeInterval(activeContext.effectiveAnalysisPreferences.sampleIntervalSeconds) else { return nil }
            lastSampleAt = now
            return activeContext
        }
        guard let active = snapshot else { return }

        let hash = imageProcessor.dHash(pixelBuffer: pixelBuffer)
        let shouldAnalyze: Bool = lock.withLock {
            let force = now.timeIntervalSince(lastAnalyzedAt ?? .distantPast) >= 60
            let changed: Bool
            if let hash, let lastHash {
                changed = DHash64.distance(hash, lastHash) >= 8
            } else {
                changed = true
            }
            if !force && !changed { return false }
            lastHash = hash
            lastAnalyzedAt = now
            isAnalyzing = true
            return true
        }
        guard shouldAnalyze,
              let jpeg = imageProcessor.jpeg(pixelBuffer: pixelBuffer, longEdge: 1_024, quality: 0.55) else {
            lock.withLock { isAnalyzing = false }
            return
        }

        Task { [weak self] in
            await self?.analyze(jpeg: jpeg, active: active, timestamp: now)
        }
    }

    private func analyze(jpeg: Data, active: ActiveSessionContext, timestamp: Date) async {
        defer { lock.withLock { isAnalyzing = false } }
        guard let provider = active.provider,
              let key = KeychainStore.loadShared(
                account: provider.id.uuidString,
                preferredAccessGroup: resolvedKeychainAccessGroup
              ),
              !key.isEmpty else {
            let shouldNotify = lock.withLock {
                guard !didNotifyConfigurationError else { return false }
                didNotifyConfigurationError = true
                return true
            }
            if shouldNotify {
                notify(
                    title: String(localized: "AI 配置不可用"),
                    body: String(localized: "广播扩展无法读取 API Key，请回到 App 重新保存 Provider。"),
                    sound: false
                )
            }
            await recordUnknown(active: active, timestamp: timestamp, reason: String(localized: "未配置可用的 AI 密钥。"))
            return
        }

        let levels = lock.withLock { recentLevels }
        let service = OpenAICompatibleVisionService(provider: provider, apiKey: key)
        let started = ContinuousClock.now
        do {
            let judgment = try await service.classifyFrame(
                FrameAnalysisInput(goal: active.goal, jpegData: jpeg, recentLevels: levels)
            )
            guard shouldAcceptResult(for: active) else { return }
            let latency = Int((ContinuousClock.now - started).milliseconds)
            let intervention = lock.withLock { () -> Intervention in
                recentLevels.append(judgment.level)
                recentLevels = Array(recentLevels.suffix(3))
                return interventionEngine.register(judgment, at: timestamp)
            }
            let shouldSaveThumbnail: Bool
            if case .audible = intervention {
                shouldSaveThumbnail = true
            } else {
                shouldSaveThumbnail = false
            }
            let thumbnailPath: String?
            if shouldSaveThumbnail,
               let sharedContainer = SharedEnvironment.appGroupContainerURL(),
               let thumbnail = makeThumbnail(from: jpeg) {
                thumbnailPath = try? ThumbnailStore.write(
                    jpegData: thumbnail,
                    sessionID: active.sessionID,
                    containerURL: sharedContainer
                )
            } else {
                thumbnailPath = nil
            }
            try? await eventStore.record(
                FocusEvent(
                    sessionID: active.sessionID,
                    timestamp: timestamp,
                    source: .visionAI,
                    level: judgment.level,
                    confidence: judgment.confidence,
                    reason: judgment.reason,
                    reminder: judgment.reminder,
                    latencyMilliseconds: latency,
                    thumbnailRelativePath: thumbnailPath
                )
            )
            deliver(
                intervention,
                preferences: active.reminderPreferences ?? ReminderPreferencesStore.load()
            )
        } catch {
            guard shouldAcceptResult(for: active) else { return }
            await recordUnknown(active: active, timestamp: timestamp, reason: String(localized: "AI 分析暂时不可用。"))
        }
    }

    private func shouldAcceptResult(for active: ActiveSessionContext) -> Bool {
        guard lock.withLock({ activeContext?.sessionID == active.sessionID }),
              let authoritative = ActiveSessionSnapshot.load(),
              authoritative.sessionID == active.sessionID,
              Date() < authoritative.endsAt else {
            return false
        }
        return true
    }

    private func recordUnknown(active: ActiveSessionContext, timestamp: Date, reason: String) async {
        guard shouldAcceptResult(for: active) else { return }
        lock.withLock {
            _ = interventionEngine.register(
                FocusJudgment(level: .unknown, confidence: 0, reason: reason, reminder: ""),
                at: timestamp
            )
        }
        try? await eventStore.record(
            FocusEvent(
                sessionID: active.sessionID,
                timestamp: timestamp,
                source: .visionAI,
                level: .unknown,
                reason: reason
            )
        )
    }

    private func makeThumbnail(from jpeg: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func deliver(_ intervention: Intervention, preferences: ReminderPreferences) {
        switch intervention {
        case .none:
            return
        case .silent(let message):
            guard preferences.silentWanderingEnabled else { return }
            notify(title: String(localized: "轻轻回到目标"), body: message, sound: false)
        case .audible(let message):
            guard preferences.audibleDistractionEnabled else { return }
            notify(title: String(localized: "专注守望提醒"), body: message, sound: true)
        }
    }

    private func notify(title: String, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = SharedConstants.notificationCategory
        content.sound = sound ? .default : nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func recordBroadcastState(_ state: BroadcastState, reason: String) {
        guard let active = lock.withLock({ activeContext }) else { return }
        try? ExtensionEventWriter.record(
            FocusEvent(
                sessionID: active.sessionID,
                source: .broadcast,
                level: .unknown,
                reason: reason,
                broadcastState: state
            )
        )
    }

    private func finishBroadcast(reason: String) {
        let request = lock.withLock { () -> (Bool, ActiveSessionContext?) in
            guard !isFinishingBroadcast else { return (false, nil) }
            isFinishingBroadcast = true
            let value = activeContext
            activeContext = nil
            return (true, value)
        }
        guard request.0 else { return }
        if let active = request.1 {
            try? ExtensionEventWriter.record(
                FocusEvent(
                    sessionID: active.sessionID,
                    source: .broadcast,
                    level: .unknown,
                    reason: reason,
                    broadcastState: .stopped
                )
            )
        }
        notify(
            title: String(localized: "屏幕广播已自动停止"),
            body: reason,
            sound: false
        )
        finishBroadcastWithError(
            NSError(
                domain: RPRecordingErrorDomain,
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        )
    }

    private var resolvedKeychainAccessGroup: String? {
        KeychainAccessGroupResolver.sharedAccessGroup()
    }
}

private extension Duration {
    var milliseconds: Int64 {
        let components = self.components
        return components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
    }
}
