import Foundation

public struct ReminderPreferences: Codable, Equatable, Sendable {
    public var silentWanderingEnabled: Bool
    public var audibleDistractionEnabled: Bool

    public init(
        silentWanderingEnabled: Bool = true,
        audibleDistractionEnabled: Bool = true
    ) {
        self.silentWanderingEnabled = silentWanderingEnabled
        self.audibleDistractionEnabled = audibleDistractionEnabled
    }
}

public enum ReminderPreferencesStore {
    public static func load(defaults: UserDefaults? = nil) -> ReminderPreferences {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        guard let data = defaults?.data(forKey: SharedConstants.reminderPreferencesDefaultsKey),
              let value = try? JSONDecoder().decode(ReminderPreferences.self, from: data) else {
            return ReminderPreferences()
        }
        return value
    }

    public static func save(
        _ preferences: ReminderPreferences,
        defaults: UserDefaults? = nil
    ) throws {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        defaults?.set(
            try JSONEncoder().encode(preferences),
            forKey: SharedConstants.reminderPreferencesDefaultsKey
        )
    }
}
