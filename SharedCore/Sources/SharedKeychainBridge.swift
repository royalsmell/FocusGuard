import Foundation
import Security

public enum SharedKeychainBridge {
    private static let activeAccount = "active-session"
    private static let eventPrefix = "event."

    public static func saveActive(_ context: ActiveSessionContext) throws {
        try KeychainStore.saveData(
            JSONEncoder.focusGuard.encode(context),
            account: activeAccount,
            service: SharedConstants.bridgeKeychainService
        )
    }

    public static func loadActive() -> ActiveSessionContext? {
        guard let data = try? KeychainStore.loadData(
            account: activeAccount,
            service: SharedConstants.bridgeKeychainService
        ) else { return nil }
        return try? JSONDecoder.focusGuard.decode(ActiveSessionContext.self, from: data)
    }

    public static func clearActive() {
        try? KeychainStore.delete(
            account: activeAccount,
            service: SharedConstants.bridgeKeychainService
        )
    }

    public static func record(_ event: FocusEvent) throws {
        try KeychainStore.saveData(
            JSONEncoder.focusGuard.encode(event),
            account: eventAccount(event),
            service: SharedConstants.bridgeKeychainService
        )
    }

    public static func drain(sessionID: UUID) -> [FocusEvent] {
        let prefix = "\(eventPrefix)\(sessionID.uuidString)."
        return matchingItems(accountPrefix: prefix).compactMap { account, data in
            defer { delete(account: account) }
            return try? JSONDecoder.focusGuard.decode(FocusEvent.self, from: data)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    public static func deleteAllEvents() {
        for (account, _) in matchingItems(accountPrefix: eventPrefix) {
            delete(account: account)
        }
    }

    private static func eventAccount(_ event: FocusEvent) -> String {
        "\(eventPrefix)\(event.sessionID.uuidString).\(event.id.uuidString)"
    }

    private static func matchingItems(accountPrefix: String) -> [(String, Data)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedConstants.bridgeKeychainService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(accountPrefix),
                  let data = item[kSecValueData as String] as? Data else {
                return nil
            }
            return (account, data)
        }
    }

    private static func delete(account: String) {
        try? KeychainStore.delete(
            account: account,
            service: SharedConstants.bridgeKeychainService
        )
    }
}
