import Foundation
import SharedCore

enum CheckFailure: Error {
    case failed(String)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

@main
struct CoreChecks {
    static func main() async throws {
        let descendingRow: [UInt8] = [9, 8, 7, 6, 5, 4, 3, 2, 1]
        let pixels = Array(repeating: descendingRow, count: 8).flatMap { $0 }
        let hash = DHash64.compute(grayscalePixels: pixels)
        try expect(hash == UInt64.max, "dHash should set all 64 bits")
        try expect(DHash64.distance(hash ?? 0, 0) == 64, "dHash distance should be 64")

        var engine = InterventionEngine()
        let distracted = FocusJudgment(
            level: .distracted,
            confidence: 0.9,
            reason: "娱乐内容",
            reminder: "回到目标"
        )
        let now = Date(timeIntervalSince1970: 1_000)
        try expect(engine.register(distracted, at: now) == .none, "first distracted frame must not alert")
        try expect(
            engine.register(distracted, at: now.addingTimeInterval(12)) == .audible(message: "回到目标"),
            "second distracted frame should alert"
        )

        let sessionID = UUID()
        let events = [
            FocusEvent(
                sessionID: sessionID,
                timestamp: now.addingTimeInterval(10),
                source: .visionAI,
                level: .focused
            ),
            FocusEvent(
                sessionID: sessionID,
                timestamp: now.addingTimeInterval(22),
                source: .visionAI,
                level: .distracted
            )
        ]
        let breakdown = SessionMetrics.breakdown(
            events: events,
            from: now,
            to: now.addingTimeInterval(40)
        )
        try expect(breakdown.focusedSeconds == 12, "focused duration should be 12 seconds")
        try expect(breakdown.distractedSeconds == 18, "distracted duration should be 18 seconds")
        try expect(breakdown.unknownSeconds == 10, "unknown duration should remain separate")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = SessionRepository(containerURL: root)
        let session = FocusSession(
            goal: "完成设计稿",
            plannedStart: now,
            plannedEnd: now.addingTimeInterval(1_500),
            mode: .broadcastAI
        )
        try await repository.upsert(session)
        let loadedSessions = try await repository.loadSessions()
        try expect(loadedSessions.first?.id == session.id, "session should round-trip")
        let activeContext = ActiveSessionContext(
            sessionID: session.id,
            goal: session.goal,
            startedAt: session.plannedStart,
            endsAt: session.plannedEnd,
            mode: session.mode,
            provider: .suggested
        )
        try await repository.saveActive(activeContext)
        try expect(
            ActiveSessionSnapshot.load(containerURL: root)?.sessionID == session.id,
            "broadcast snapshot should observe active session"
        )
        try await repository.clearActive()
        try expect(
            ActiveSessionSnapshot.load(containerURL: root) == nil,
            "cleared session should stop broadcast processing"
        )

        let eventStore = SharedEventStore(containerURL: root)
        try await eventStore.record(events[0])
        let drainedEvents = try await eventStore.drain(sessionID: sessionID)
        try expect(drainedEvents.count == 1, "event should drain once")

        let provider = ProviderConfig(
            name: "Test",
            baseURL: URL(string: "https://example.com/v1")!,
            model: "vision"
        )
        try expect(
            provider.chatCompletionsURL.absoluteString == "https://example.com/v1/chat/completions",
            "provider URL should normalize"
        )
        let trailingSlashProvider = ProviderConfig(
            name: "Test",
            baseURL: URL(string: "https://example.com/v1/")!,
            model: "vision"
        )
        try expect(
            trailingSlashProvider.chatCompletionsURL.absoluteString == "https://example.com/v1/chat/completions",
            "provider URL with trailing slash should normalize"
        )
        try expect(
            OpenAICompatibleVisionService.cleanJSON("```json\n{\"level\":\"focused\"}\n```") == #"{"level":"focused"}"#,
            "JSON fences should be removed"
        )

        let thumbnailPath = try ThumbnailStore.write(
            jpegData: Data([1, 2, 3]),
            sessionID: sessionID,
            containerURL: root
        )
        let thumbnailURL = root.appendingPathComponent(thumbnailPath)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: thumbnailURL.path
        )
        let removed = try ThumbnailStore.removeExpired(olderThan: 30, now: Date(), containerURL: root)
        try expect(removed == 1, "expired thumbnail should be removed")

        print("Core checks passed")
    }
}
