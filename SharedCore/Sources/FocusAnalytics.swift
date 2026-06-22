import Foundation

public enum AnalyticsScope: String, CaseIterable, Sendable {
    case session
    case day
    case week
    case year
}

public struct AnalyticsSummary: Equatable, Sendable {
    public let sessionCount: Int
    public let completionRate: Double
    public let focusedSeconds: TimeInterval
    public let averageCoverage: Double

    public init(sessionCount: Int, completionRate: Double, focusedSeconds: TimeInterval, averageCoverage: Double) {
        self.sessionCount = sessionCount
        self.completionRate = completionRate
        self.focusedSeconds = focusedSeconds
        self.averageCoverage = averageCoverage
    }
}

public struct AnalyticsRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let periodStart: Date
    public let title: String
    public let sessionCount: Int
    public let completedCount: Int
    public let totalSeconds: TimeInterval
    public let breakdown: FocusBreakdown
    public let status: SessionStatus?

    public var completionRate: Double {
        guard sessionCount > 0 else { return 0 }
        return Double(completedCount) / Double(sessionCount)
    }

    public var coverage: Double { breakdown.coverage }

    public var statusSegments: [AnalyticsStatusSegment] {
        breakdown.statusSegments
    }
}

public struct AnalyticsReport: Equatable, Sendable {
    public let summary: AnalyticsSummary
    public let rows: [AnalyticsRow]
    public let breakdown: FocusBreakdown

    public var statusSegments: [AnalyticsStatusSegment] {
        breakdown.statusSegments
    }
}

public struct AnalyticsStatusSegment: Identifiable, Equatable, Sendable {
    public let level: FocusLevel
    public let seconds: TimeInterval

    public var id: FocusLevel { level }

    public init(level: FocusLevel, seconds: TimeInterval) {
        self.level = level
        self.seconds = max(0, seconds)
    }
}

public extension FocusBreakdown {
    var statusSegments: [AnalyticsStatusSegment] {
        [
            AnalyticsStatusSegment(level: .focused, seconds: focusedSeconds),
            AnalyticsStatusSegment(level: .wandering, seconds: wanderingSeconds),
            AnalyticsStatusSegment(level: .distracted, seconds: distractedSeconds),
            AnalyticsStatusSegment(level: .unknown, seconds: unknownSeconds)
        ]
    }
}

public enum FocusAnalytics {
    public static func report(
        sessions: [FocusSession],
        scope: AnalyticsScope,
        calendar sourceCalendar: Calendar = .current
    ) -> AnalyticsReport {
        let sessions = sessions.filter { $0.status != .active }
        let rows: [AnalyticsRow]
        switch scope {
        case .session:
            rows = sessions
                .sorted { $0.plannedStart > $1.plannedStart }
                .map {
                    AnalyticsRow(
                        id: $0.id.uuidString,
                        periodStart: $0.plannedStart,
                        title: $0.goal,
                        sessionCount: 1,
                        completedCount: $0.status == .completed ? 1 : 0,
                        totalSeconds: $0.duration,
                        breakdown: $0.breakdown,
                        status: $0.status
                    )
                }
        case .day, .week, .year:
            var calendar = sourceCalendar
            calendar.firstWeekday = 2
            let groups = Dictionary(grouping: sessions) { session in
                periodStart(for: session.plannedStart, scope: scope, calendar: calendar)
            }
            rows = groups.map { date, values in
                let breakdown = values.reduce(into: FocusBreakdown()) { result, session in
                    result.focusedSeconds += session.breakdown.focusedSeconds
                    result.wanderingSeconds += session.breakdown.wanderingSeconds
                    result.distractedSeconds += session.breakdown.distractedSeconds
                    result.unknownSeconds += session.breakdown.unknownSeconds
                }
                return AnalyticsRow(
                    id: "\(scope.rawValue)-\(date.timeIntervalSince1970)",
                    periodStart: date,
                    title: periodTitle(date, scope: scope, calendar: calendar),
                    sessionCount: values.count,
                    completedCount: values.filter { $0.status == .completed }.count,
                    totalSeconds: values.reduce(0) { $0 + $1.duration },
                    breakdown: breakdown,
                    status: nil
                )
            }.sorted { $0.periodStart > $1.periodStart }
        }

        let totalBreakdown = sessions.reduce(into: FocusBreakdown()) { result, session in
            result.focusedSeconds += session.breakdown.focusedSeconds
            result.wanderingSeconds += session.breakdown.wanderingSeconds
            result.distractedSeconds += session.breakdown.distractedSeconds
            result.unknownSeconds += session.breakdown.unknownSeconds
        }
        let completionRate = sessions.isEmpty
            ? 0
            : Double(sessions.filter { $0.status == .completed }.count) / Double(sessions.count)
        let averageCoverage = sessions.isEmpty
            ? 0
            : sessions.reduce(0) { $0 + $1.breakdown.coverage } / Double(sessions.count)
        return AnalyticsReport(
            summary: AnalyticsSummary(
                sessionCount: sessions.count,
                completionRate: completionRate,
                focusedSeconds: totalBreakdown.focusedSeconds,
                averageCoverage: averageCoverage
            ),
            rows: rows,
            breakdown: totalBreakdown
        )
    }

    private static func periodStart(for date: Date, scope: AnalyticsScope, calendar: Calendar) -> Date {
        switch scope {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let weekday = calendar.component(.weekday, from: date)
            let daysFromMonday = (weekday - 2 + 7) % 7
            return calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: date)) ?? date
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        case .session:
            return date
        }
    }

    private static func periodTitle(_ date: Date, scope: AnalyticsScope, calendar: Calendar) -> String {
        switch scope {
        case .day:
            return date.formatted(.dateTime.year().month().day())
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: date) ?? date
            return "\(date.formatted(.dateTime.month().day()))–\(end.formatted(.dateTime.month().day()))"
        case .year:
            return date.formatted(.dateTime.year())
        case .session:
            return date.formatted()
        }
    }
}
