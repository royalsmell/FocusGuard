import Foundation

public enum SharedConstants {
    public static let appGroupIdentifier = "group.com.huangjiawen.focusguard"
    public static let keychainAccessGroupSuffix = "com.huangjiawen.focusguard.shared"
    public static let providerDefaultsKey = "ai.provider.configuration"
    public static let providerListDefaultsKey = "ai.provider.configurations.list"
    public static let activeProviderIDDefaultsKey = "ai.provider.active.id"
    public static let providerListDefaultsKey = "ai.provider.configurations.list"
    public static let activeProviderIDDefaultsKey = "ai.provider.active.id"
    public static let reminderPreferencesDefaultsKey = "reminders.preferences"
    public static let durationPreferencesDefaultsKey = "focus.duration.preferences"
    public static let analysisPreferencesDefaultsKey = "analysis.preferences"
    public static let preferenceModificationDatesDefaultsKey = "preferences.modified-at"
    public static let notificationCategory = "FOCUS_GUARD_ALERT"
    public static let broadcastExtensionBundleIdentifier = "com.huangjiawen.focusguard.BroadcastUpload"
    public static let bridgeKeychainService = "FocusGuard.CrossProcessBridge"
}

public enum SharedEnvironment {
    public static func appGroupContainerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier
        )
    }

    public static func containerURL(fileManager: FileManager = .default) -> URL {
        if let groupURL = appGroupContainerURL(fileManager: fileManager) {
            return groupURL
        }

        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusGuard", isDirectory: true)
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
