import Foundation

public struct FocusDurationComponents: Equatable, Sendable {
    public let hours: Int
    public let minutes: Int

    public init(hours: Int, minutes: Int) {
        self.hours = hours
        self.minutes = minutes
    }
}

public enum FocusDuration {
    public static let maximumMinutes = 23 * 60 + 59

    public static func totalMinutes(hours: Int, minutes: Int) -> Int {
        max(0, hours) * 60 + max(0, minutes)
    }

    public static func components(totalMinutes: Int) -> FocusDurationComponents {
        let clamped = min(max(0, totalMinutes), maximumMinutes)
        return FocusDurationComponents(hours: clamped / 60, minutes: clamped % 60)
    }
}
