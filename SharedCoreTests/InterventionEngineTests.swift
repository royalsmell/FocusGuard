import Foundation
import XCTest
@testable import SharedCore

final class InterventionEngineTests: XCTestCase {
    func testDistractedRequiresTwoConfidentFrames() {
        var engine = InterventionEngine()
        let judgment = FocusJudgment(
            level: .distracted,
            confidence: 0.9,
            reason: "正在浏览娱乐内容",
            reminder: "回到目标"
        )
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(engine.register(judgment, at: now), .none)
        XCTAssertEqual(engine.register(judgment, at: now.addingTimeInterval(12)), .audible(message: "回到目标"))
        XCTAssertEqual(engine.register(judgment, at: now.addingTimeInterval(24)), .none)
        XCTAssertEqual(engine.register(judgment, at: now.addingTimeInterval(36)), .none)
    }

    func testDistractedCooldownAllowsANewAlertAfterSixtySeconds() {
        var engine = InterventionEngine()
        let judgment = FocusJudgment(
            level: .distracted,
            confidence: 0.9,
            reason: "正在浏览娱乐内容",
            reminder: "回到目标"
        )
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(engine.register(judgment, at: now), .none)
        XCTAssertEqual(engine.register(judgment, at: now.addingTimeInterval(12)), .audible(message: "回到目标"))
        XCTAssertEqual(engine.register(judgment, at: now.addingTimeInterval(60)), .none)
        XCTAssertEqual(engine.register(judgment, at: now.addingTimeInterval(72)), .audible(message: "回到目标"))
    }

    func testLowConfidenceNeverAlerts() {
        var engine = InterventionEngine()
        let judgment = FocusJudgment(level: .distracted, confidence: 0.4, reason: "", reminder: "提醒")
        for offset in 0..<5 {
            XCTAssertEqual(engine.register(judgment, at: Date(timeIntervalSince1970: Double(offset))), .none)
        }
    }

    func testUnknownResultBreaksDistractedStreak() {
        var engine = InterventionEngine()
        let distracted = FocusJudgment(level: .distracted, confidence: 0.9, reason: "", reminder: "提醒")
        let unknown = FocusJudgment(level: .unknown, confidence: 0, reason: "网络失败", reminder: "")
        XCTAssertEqual(engine.register(distracted), .none)
        XCTAssertEqual(engine.register(unknown), .none)
        XCTAssertEqual(engine.register(distracted), .none)
        XCTAssertEqual(engine.register(distracted), .audible(message: "提醒"))
    }

    func testWanderingRequiresThreeFrames() {
        var engine = InterventionEngine()
        let judgment = FocusJudgment(level: .wandering, confidence: 0.8, reason: "", reminder: "轻轻回来")
        XCTAssertEqual(engine.register(judgment), .none)
        XCTAssertEqual(engine.register(judgment), .none)
        XCTAssertEqual(engine.register(judgment), .silent(message: "轻轻回来"))
    }
}
