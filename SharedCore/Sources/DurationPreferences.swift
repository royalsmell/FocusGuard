import Foundation

public struct DurationPreferences: Codable, Equatable, Sendable {
    public static let defaultQuickMinutes = [10, 15, 25, 45, 60]
    public static let allowedMinutes = 1...FocusDuration.maximumMinutes

    public var quickMinutes: [Int]

    public init(quickMinutes: [Int] = Self.defaultQuickMinutes) {
        self.quickMinutes = Self.validated(quickMinutes)
    }

    public static func validated(_ values: [Int]) -> [Int] {
        guard values.count == 5, values.allSatisfy(allowedMinutes.contains) else {
            return defaultQuickMinutes
        }
        return values
    }
}

public enum DurationPreferencesStore {
    public static func load(defaults: UserDefaults? = nil) -> DurationPreferences {
        let data: Data?
        if let defaults {
            data = defaults.data(forKey: SharedConstants.durationPreferencesDefaultsKey)
        } else {
            data = UserDefaults(suiteName: SharedConstants.appGroupIdentifier)?
                .data(forKey: SharedConstants.durationPreferencesDefaultsKey)
                ?? UserDefaults.standard.data(forKey: SharedConstants.durationPreferencesDefaultsKey)
        }
        guard let data,
              let decoded = try? JSONDecoder().decode(DurationPreferences.self, from: data) else {
            return DurationPreferences()
        }
        return DurationPreferences(quickMinutes: decoded.quickMinutes)
    }

    public static func save(
        _ preferences: DurationPreferences,
        defaults: UserDefaults? = nil
    ) throws {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier) ?? .standard
        let validated = DurationPreferences(quickMinutes: preferences.quickMinutes)
        defaults.set(
            try JSONEncoder().encode(validated),
            forKey: SharedConstants.durationPreferencesDefaultsKey
        )
    }
}
