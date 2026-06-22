import Foundation
import XCTest
@testable import SharedCore

final class BackupAndAnalyticsTests: XCTestCase {
    func testArchiveRoundTripIncludesAPIKeyAndThumbnail() throws {
        let sessionID = UUID()
        let event = FocusEvent(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            source: .visionAI,
            level: .distracted,
            thumbnailRelativePath: "thumbnails/\(sessionID.uuidString)/sample.jpg"
        )
        let session = FocusSession(
            id: sessionID,
            goal: "完成测试",
            plannedStart: Date(timeIntervalSince1970: 1_700_000_000),
            plannedEnd: Date(timeIntervalSince1970: 1_700_000_600),
            actualEnd: Date(timeIntervalSince1970: 1_700_000_600),
            mode: .broadcastAI,
            status: .completed,
            events: [event],
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_601)
        )
        let envelope = makeEnvelope(
            sessions: [session],
            thumbnails: [
                BackupThumbnail(
                    eventID: event.id,
                    sessionID: sessionID,
                    relativePath: event.thumbnailRelativePath!,
                    jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9])
                )
            ]
        )
        let encoded = try BackupArchiveCodec.encode(envelope)
        let decoded = try BackupArchiveCodec.decode(encoded)
        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.preferences.apiKey, "secret-in-archive")
    }

    func testArchiveRejectsCorruptionAndUnsupportedSchema() throws {
        let archive = try BackupArchiveCodec.encode(makeEnvelope())
        var corrupted = archive
        corrupted[corrupted.count - 1] ^= 0x01
        XCTAssertThrowsError(try BackupArchiveCodec.decode(corrupted)) { error in
            XCTAssertEqual(error as? BackupArchiveError, .integrityCheckFailed)
        }

        var wrongSchema = archive
        wrongSchema[4] = 0
        wrongSchema[5] = 2
        XCTAssertThrowsError(try BackupArchiveCodec.decode(wrongSchema)) { error in
            XCTAssertEqual(error as? BackupArchiveError, .unsupportedSchema(2))
        }
    }

    func testMergeUsesNewerMetadataAndUnionsEventsWithoutDeletingLocal() {
        let id = UUID()
        let localEvent = FocusEvent(sessionID: id, source: .visionAI, level: .focused)
        let importedEvent = FocusEvent(sessionID: id, source: .visionAI, level: .distracted)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let local = FocusSession(
            id: id,
            goal: "旧目标",
            plannedStart: start,
            plannedEnd: start.addingTimeInterval(600),
            actualEnd: start.addingTimeInterval(600),
            mode: .broadcastAI,
            status: .completed,
            events: [localEvent],
            modifiedAt: start
        )
        let imported = FocusSession(
            id: id,
            goal: "新目标",
            plannedStart: start,
            plannedEnd: start.addingTimeInterval(600),
            actualEnd: start.addingTimeInterval(600),
            mode: .broadcastAI,
            status: .completed,
            events: [importedEvent],
            modifiedAt: start.addingTimeInterval(30)
        )
        let localOnly = FocusSession(goal: "本机独有", plannedEnd: .now, mode: .broadcastAI, status: .completed)
        let result = BackupMerger.merge(
            localSessions: [local, localOnly],
            archive: makeEnvelope(sessions: [imported]),
            localModificationDates: .init()
        )
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(result.sessions.first(where: { $0.id == id })?.goal, "新目标")
        XCTAssertEqual(result.sessions.first(where: { $0.id == id })?.events.count, 2)
        XCTAssertNotNil(result.sessions.first(where: { $0.id == localOnly.id }))
        XCTAssertEqual(result.preview.updatedSessionCount, 1)
    }

    func testAnalysisPreferencesAllowOnlyFourIntervalsAndOldContextDefaultsToTwelve() throws {
        XCTAssertEqual(AnalysisPreferences.allowedSampleIntervals, [5, 12, 30, 60])
        XCTAssertEqual(AnalysisPreferences(sampleIntervalSeconds: 7).sampleIntervalSeconds, 12)

        let json = """
        {"sessionID":"00000000-0000-0000-0000-000000000001","goal":"测试","startedAt":1700000000,"endsAt":1700000600,"mode":"broadcastAI","provider":null,"reminderPreferences":null}
        """.data(using: .utf8)!
        let context = try JSONDecoder.focusGuard.decode(ActiveSessionContext.self, from: json)
        XCTAssertEqual(context.effectiveAnalysisPreferences.sampleIntervalSeconds, 12)
    }

    func testAnalyticsUsesMondayWeekAndExcludesActiveSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        func session(_ start: Date, status: SessionStatus) -> FocusSession {
            FocusSession(
                goal: "统计",
                plannedStart: start,
                plannedEnd: start.addingTimeInterval(600),
                actualEnd: start.addingTimeInterval(600),
                mode: .broadcastAI,
                status: status,
                breakdown: FocusBreakdown(focusedSeconds: 300, unknownSeconds: 300)
            )
        }
        let report = FocusAnalytics.report(
            sessions: [session(monday, status: .completed), session(sunday, status: .cancelled), session(nextMonday, status: .completed), session(nextMonday, status: .active)],
            scope: .week,
            calendar: calendar
        )
        XCTAssertEqual(report.summary.sessionCount, 3)
        XCTAssertEqual(report.rows.count, 2)
        XCTAssertEqual(report.rows.last?.sessionCount, 2)
        XCTAssertEqual(report.summary.averageCoverage, 0.5, accuracy: 0.001)
        XCTAssertEqual(report.statusSegments.map(\.level), FocusLevel.allCases)
        XCTAssertEqual(
            report.statusSegments.first(where: { $0.level == .focused })?.seconds,
            900
        )
        XCTAssertEqual(
            report.rows.first?.statusSegments.first(where: { $0.level == .unknown })?.seconds,
            300
        )
    }

    func testRewriteJSONDecodesStrictResult() async throws {
        let service = OpenAICompatibleVisionService(provider: .suggested, apiKey: "test")
        let result = try service.decodeJSON(
            GoalRewriteResult.self,
            from: #"{"rewrittenGoal":"完成第一版提纲","reason":"更具体"}"#
        )
        XCTAssertEqual(result.rewrittenGoal, "完成第一版提纲")
    }

    private func makeEnvelope(
        sessions: [FocusSession] = [],
        thumbnails: [BackupThumbnail] = []
    ) -> BackupEnvelope {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BackupEnvelope(
            manifest: BackupManifest(exportedAt: date, appVersion: "1.2.0", sessionCount: sessions.count),
            sessions: sessions,
            preferences: BackupPreferences(
                provider: .suggested,
                providerModifiedAt: date,
                apiKey: "secret-in-archive",
                reminders: .init(),
                remindersModifiedAt: date,
                quickDurations: .init(),
                quickDurationsModifiedAt: date,
                analysis: .init(),
                analysisModifiedAt: date
            ),
            thumbnails: thumbnails
        )
    }
}
