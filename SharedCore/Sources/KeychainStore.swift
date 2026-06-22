import Foundation
import Security

public enum KeychainStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

public enum KeychainStore {
    public static func save(
        _ value: String,
        account: String,
        service: String = "FocusGuard.AI",
        accessGroup: String? = nil
    ) throws {
        try saveData(
            Data(value.utf8),
            account: account,
            service: service,
            accessGroup: accessGroup
        )
    }

    public static func saveData(
        _ data: Data,
        account: String,
        service: String = "FocusGuard.AI",
        accessGroup: String? = nil
    ) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(addStatus) }
    }

    public static func load(
        account: String,
        service: String = "FocusGuard.AI",
        accessGroup: String? = nil
    ) throws -> String? {
        guard let data = try loadData(
            account: account,
            service: service,
            accessGroup: accessGroup
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func loadData(
        account: String,
        service: String = "FocusGuard.AI",
        accessGroup: String? = nil
    ) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        return result as? Data
    }

    public static func delete(
        account: String,
        service: String = "FocusGuard.AI",
        accessGroup: String? = nil
    ) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    public static func saveShared(
        _ value: String,
        account: String,
        service: String = "FocusGuard.AI",
        preferredAccessGroup: String?
    ) throws {
        if let preferredAccessGroup {
            do {
                try save(value, account: account, service: service, accessGroup: preferredAccessGroup)
                return
            } catch {
                // Self-sign profiles often remove custom access groups. Their default
                // group may still be shared by the containing app and extensions.
            }
        }
        try save(value, account: account, service: service)
    }

    public static func loadShared(
        account: String,
        service: String = "FocusGuard.AI",
        preferredAccessGroup: String?
    ) -> String? {
        if let preferredAccessGroup,
           let value = try? load(
               account: account,
               service: service,
               accessGroup: preferredAccessGroup
           ) {
            return value
        }
        return try? load(account: account, service: service)
    }

    public static func deleteShared(
        account: String,
        service: String = "FocusGuard.AI",
        preferredAccessGroup: String?
    ) {
        if let preferredAccessGroup {
            try? delete(account: account, service: service, accessGroup: preferredAccessGroup)
        }
        try? delete(account: account, service: service)
    }
}
