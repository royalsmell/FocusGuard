import Foundation

public enum SessionMetrics {
    public static func breakdown(
        events: [FocusEvent],
        from start: Date,
        to end: Date,
        maximumEventWeight: TimeInterval = 60
    ) -> FocusBreakdown {
        guard end > start else { return .init() }
        let visionEvents = events
            .filter { $0.source == .visionAI && $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }
        let observationBoundaries = events
            .filter {
                $0.source == .broadcast
                    && $0.timestamp >= start
                    && $0.timestamp <= end
                    && ($0.broadcastState == .paused || $0.broadcastState == .stopped)
            }
            .map(\.timestamp)
            .sorted()

        var result = FocusBreakdown()
        var cursor = start

        for (index, event) in visionEvents.enumerated() {
            if event.timestamp > cursor {
                result.unknownSeconds += event.timestamp.timeIntervalSince(cursor)
            }
            let nextVisionTimestamp = index + 1 < visionEvents.count ? visionEvents[index + 1].timestamp : end
            let nextBoundary = observationBoundaries.first(where: { $0 > event.timestamp }) ?? end
            let nextTimestamp = min(nextVisionTimestamp, nextBoundary, end)
            let weight = max(0, min(maximumEventWeight, nextTimestamp.timeIntervalSince(event.timestamp)))
            add(weight, level: event.level, to: &result)
            cursor = max(cursor, event.timestamp.addingTimeInterval(weight))
        }

        if cursor < end {
            result.unknownSeconds += end.timeIntervalSince(cursor)
        }
        return result
    }

    private static func add(_ seconds: TimeInterval, level: FocusLevel, to result: inout FocusBreakdown) {
        switch level {
        case .focused: result.focusedSeconds += seconds
        case .wandering: result.wanderingSeconds += seconds
        case .distracted: result.distractedSeconds += seconds
        case .unknown: result.unknownSeconds += seconds
        }
    }
}
