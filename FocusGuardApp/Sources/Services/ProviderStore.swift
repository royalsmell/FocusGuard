import Foundation
import Observation
import SharedCore

@MainActor
@Observable
final class ProviderStore {
    private(set) var configuration: ProviderConfig
    private(set) var hasAPIKey = false
    private(set) var modifiedAt: Date

    private let defaults: UserDefaults

    init() {
        self.defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) ?? .standard
        self.modifiedAt = PreferenceModificationDatesStore.load(defaults: self.defaults).provider
        if let data = defaults.data(forKey: SharedConstants.providerDefaultsKey),
           let value = try? JSONDecoder().decode(ProviderConfig.self, from: data) {
            self.configuration = value
        } else {
            self.configuration = .suggested
        }
        refreshKeyStatus()
    }

    func save(configuration: ProviderConfig, apiKey: String?) throws {
        try save(configuration: configuration, apiKey: apiKey, modifiedAt: .now)
    }

    func applyImported(configuration: ProviderConfig, apiKey: String?, modifiedAt: Date) throws {
        let preservedKey = apiKey ?? loadAPIKey()
        try save(configuration: configuration, apiKey: preservedKey, modifiedAt: modifiedAt)
    }

    private func save(configuration: ProviderConfig, apiKey: String?, modifiedAt: Date) throws {
        if configuration.id != self.configuration.id {
            KeychainStore.deleteShared(
                account: self.configuration.id.uuidString,
                preferredAccessGroup: keychainAccessGroup
            )
        }
        self.configuration = configuration
        defaults.set(try JSONEncoder().encode(configuration), forKey: SharedConstants.providerDefaultsKey)
        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try KeychainStore.saveShared(
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                account: configuration.id.uuidString,
                preferredAccessGroup: keychainAccessGroup
            )
        }
        self.modifiedAt = modifiedAt
        var dates = PreferenceModificationDatesStore.load(defaults: defaults)
        dates.provider = modifiedAt
        try PreferenceModificationDatesStore.save(dates, defaults: defaults)
        refreshKeyStatus()
    }

    func loadAPIKey() -> String? {
        KeychainStore.loadShared(
            account: configuration.id.uuidString,
            preferredAccessGroup: keychainAccessGroup
        )
    }

    func deleteAPIKey() throws {
        KeychainStore.deleteShared(
            account: configuration.id.uuidString,
            preferredAccessGroup: keychainAccessGroup
        )
        modifiedAt = .now
        var dates = PreferenceModificationDatesStore.load(defaults: defaults)
        dates.provider = modifiedAt
        try PreferenceModificationDatesStore.save(dates, defaults: defaults)
        refreshKeyStatus()
    }

    func makeService() -> OpenAICompatibleVisionService? {
        guard let key = loadAPIKey(), !key.isEmpty else { return nil }
        return OpenAICompatibleVisionService(provider: configuration, apiKey: key)
    }

    private func refreshKeyStatus() {
        hasAPIKey = !(loadAPIKey() ?? "").isEmpty
    }

    private var keychainAccessGroup: String? {
        KeychainAccessGroupResolver.sharedAccessGroup()
    }
}
