import Foundation

public struct AnalysisPreferences: Codable, Equatable, Sendable {
    public static let allowedSampleIntervals = [5, 12, 30, 60]

    public var sampleIntervalSeconds: Int

    public init(sampleIntervalSeconds: Int = 12) {
        self.sampleIntervalSeconds = Self.allowedSampleIntervals.contains(sampleIntervalSeconds)
            ? sampleIntervalSeconds
            : 12
    }
}

public enum AnalysisPreferencesStore {
    public static func load(defaults: UserDefaults? = nil) -> AnalysisPreferences {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        guard let data = defaults?.data(forKey: SharedConstants.analysisPreferencesDefaultsKey),
              let value = try? JSONDecoder().decode(AnalysisPreferences.self, from: data) else {
            return AnalysisPreferences()
        }
        return AnalysisPreferences(sampleIntervalSeconds: value.sampleIntervalSeconds)
    }

    public static func save(
        _ preferences: AnalysisPreferences,
        defaults: UserDefaults? = nil
    ) throws {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        defaults?.set(
            try JSONEncoder().encode(AnalysisPreferences(sampleIntervalSeconds: preferences.sampleIntervalSeconds)),
            forKey: SharedConstants.analysisPreferencesDefaultsKey
        )
    }
}

public struct PreferenceModificationDates: Codable, Equatable, Sendable {
    public var provider: Date
    public var reminders: Date
    public var quickDurations: Date
    public var analysis: Date

    public init(
        provider: Date = .distantPast,
        reminders: Date = .distantPast,
        quickDurations: Date = .distantPast,
        analysis: Date = .distantPast
    ) {
        self.provider = provider
        self.reminders = reminders
        self.quickDurations = quickDurations
        self.analysis = analysis
    }
}

public enum PreferenceModificationDatesStore {
    public static func load(defaults: UserDefaults? = nil) -> PreferenceModificationDates {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        guard let data = defaults?.data(forKey: SharedConstants.preferenceModificationDatesDefaultsKey),
              let value = try? JSONDecoder().decode(PreferenceModificationDates.self, from: data) else {
            return PreferenceModificationDates()
        }
        return value
    }

    public static func save(
        _ dates: PreferenceModificationDates,
        defaults: UserDefaults? = nil
    ) throws {
        let defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        defaults?.set(
            try JSONEncoder().encode(dates),
            forKey: SharedConstants.preferenceModificationDatesDefaultsKey
        )
    }
}
