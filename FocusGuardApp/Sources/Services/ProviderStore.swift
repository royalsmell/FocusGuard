import Foundation
import Observation
import SharedCore

@MainActor
@Observable
final class ProviderStore {
    private(set) var providers: [ProviderConfig] = []
    private(set) var activeProviderID: UUID
    private(set) var hasAPIKey = false
    private(set) var modifiedAt: Date

    private let defaults: UserDefaults

    var configuration: ProviderConfig {
        providers.first { $0.id == activeProviderID } ?? providers.first ?? .suggested
    }

    init() {
        self.defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) ?? .standard
        self.modifiedAt = PreferenceModificationDatesStore.load(defaults: self.defaults).provider

        // Load list and active ID
        var loadedProviders: [ProviderConfig] = []
        if let data = defaults.data(forKey: SharedConstants.providerListDefaultsKey),
           let list = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            loadedProviders = list
        } else if let data = defaults.data(forKey: SharedConstants.providerDefaultsKey),
                  let single = try? JSONDecoder().decode(ProviderConfig.self, from: data) {
            loadedProviders = [single]
        }

        if loadedProviders.isEmpty {
            loadedProviders = [.suggested]
        }
        self.providers = loadedProviders

        if let idString = defaults.string(forKey: SharedConstants.activeProviderIDDefaultsKey),
           let id = UUID(uuidString: idString),
           loadedProviders.contains(where: { $0.id == id }) {
            self.activeProviderID = id
        } else {
            self.activeProviderID = loadedProviders.first!.id
        }

        refreshKeyStatus()
    }

    func setActiveProvider(id: UUID) {
        if providers.contains(where: { $0.id == id }) {
            self.activeProviderID = id
            defaults.set(id.uuidString, forKey: SharedConstants.activeProviderIDDefaultsKey)
            refreshKeyStatus()
        }
    }

    func save(configuration: ProviderConfig, apiKey: *** throws {
        try save(configuration: configuration, apiKey: *** modifiedAt: .now)
    }

    func applyImported(configuration: ProviderConfig, apiKey: *** modifiedAt: Date) throws {
        let preservedKey = apiKey ?? loadAPIKey(for: configuration.id)
        try save(configuration: configuration, apiKey: *** modifiedAt: modifiedAt)
    }

    private func save(configuration: ProviderConfig, apiKey: *** modifiedAt: Date) throws {
        if let index = providers.firstIndex(where: { $0.id == configuration.id }) {
            providers[index] = configuration
        } else {
            providers.append(configuration)
        }
        
        defaults.set(try JSONEncoder().encode(providers), forKey: SharedConstants.providerListDefaultsKey)
        
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
        
        // If this is the first provider or the active one, refresh
        if activeProviderID == configuration.id || providers.count == 1 {
            if providers.count == 1 {
                setActiveProvider(id: configuration.id)
            }
            refreshKeyStatus()
        }
    }

    func deleteProvider(id: UUID) {
        KeychainStore.deleteShared(
            account: id.uuidString,
            preferredAccessGroup: keychainAccessGroup
        )
        providers.removeAll { $0.id == id }
        defaults.set(try? JSONEncoder().encode(providers), forKey: SharedConstants.providerListDefaultsKey)
        
        if activeProviderID == id {
            if let first = providers.first {
                setActiveProvider(id: first.id)
            }
        }
        refreshKeyStatus()
    }

    func loadAPIKey() -> String? {
        loadAPIKey(for: configuration.id)
    }

    func loadAPIKey(for id: UUID) -> String? {
        KeychainStore.loadShared(
            account: id.uuidString,
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
        return OpenAICompatibleVisionService(provider: configuration, apiKey: ***
    }

    private func refreshKeyStatus() {
        hasAPIKey = !(loadAPIKey() ?? "").isEmpty
    }

    private var keychainAccessGroup: String? {
        KeychainAccessGroupResolver.sharedAccessGroup()
    }
}
