import Foundation
import XCTest
@testable import SharedCore

final class SessionMetricsTests: XCTestCase {
    func testLegacySessionModesMigrateToBroadcastAI() throws {
        for rawValue in ["screenTimeOnly", "hybridAI", "broadcastAIOnly", "broadcastAI"] {
            let data = try XCTUnwrap("\"\(rawValue)\"".data(using: .utf8))
            XCTAssertEqual(try JSONDecoder().decode(SessionMode.self, from: data), .broadcastAI)
        }
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(SessionMode.broadcastAI), encoding: .utf8),
            "\"broadcastAI\""
        )
    }

    func testLegacyShieldEventMigratesToSystem() throws {
        let data = try XCTUnwrap("\"screenTimeShield\"".data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode(EventSource.self, from: data), .system)
    }

    func testBroadcastLifecycleFinishesExpiredOrClearedSession() {
        let now = Date(timeIntervalSince1970: 1_000)
        let active = ActiveSessionContext(
            sessionID: UUID(),
            goal: "写文档",
            startedAt: now,
            endsAt: now.addingTimeInterval(60),
            mode: .broadcastAI,
            provider: .suggested
        )
        XCTAssertFalse(BroadcastLifecycle.shouldFinish(active: active, authoritative: active, now: now))
        XCTAssertTrue(BroadcastLifecycle.shouldFinish(active: active, authoritative: nil, now: now))
        XCTAssertTrue(
            BroadcastLifecycle.shouldFinish(
                active: active,
                authoritative: active,
                now: active.endsAt
            )
        )
    }

    func testMetricsKeepUnobservedTimeSeparate() {
        let start = Date(timeIntervalSince1970: 0)
        let sessionID = UUID()
        let events = [
            FocusEvent(
                sessionID: sessionID,
                timestamp: start.addingTimeInterval(10),
                source: .visionAI,
                level: .focused
            ),
            FocusEvent(
                sessionID: sessionID,
                timestamp: start.addingTimeInterval(22),
                source: .visionAI,
                level: .distracted
            )
        ]

        let value = SessionMetrics.breakdown(events: events, from: start, to: start.addingTimeInterval(40))
        XCTAssertEqual(value.focusedSeconds, 12)
        XCTAssertEqual(value.distractedSeconds, 18)
        XCTAssertEqual(value.unknownSeconds, 10)
        XCTAssertEqual(value.coverage, 0.75)
    }

    func testNonVisionEventsDoNotBecomeObservedTime() {
        let start = Date(timeIntervalSince1970: 0)
        let event = FocusEvent(
            sessionID: UUID(),
            timestamp: start.addingTimeInterval(5),
            source: .system,
            level: .distracted
        )
        let value = SessionMetrics.breakdown(events: [event], from: start, to: start.addingTimeInterval(30))
        XCTAssertEqual(value.unknownSeconds, 30)
        XCTAssertEqual(value.observedSeconds, 0)
    }

    func testBroadcastStopCapsLastObservedInterval() {
        let start = Date(timeIntervalSince1970: 0)
        let sessionID = UUID()
        let events = [
            FocusEvent(
                sessionID: sessionID,
                timestamp: start.addingTimeInterval(10),
                source: .visionAI,
                level: .focused
            ),
            FocusEvent(
                sessionID: sessionID,
                timestamp: start.addingTimeInterval(15),
                source: .broadcast,
                level: .unknown,
                reason: "AI 屏幕广播已停止。",
                broadcastState: .stopped
            )
        ]

        let value = SessionMetrics.breakdown(events: events, from: start, to: start.addingTimeInterval(40))
        XCTAssertEqual(value.focusedSeconds, 5)
        XCTAssertEqual(value.unknownSeconds, 35)
        XCTAssertEqual(value.coverage, 0.125)
    }
}
