import Foundation
import Security

public enum KeychainAccessGroupResolver {
    public static func sharedAccessGroup() -> String? {
        guard let defaultAccessGroup = readDefaultAccessGroup(),
              let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return nil
        }
        return sharedAccessGroup(
            defaultAccessGroup: defaultAccessGroup,
            bundleIdentifier: bundleIdentifier
        )
    }

    public static func sharedAccessGroup(
        defaultAccessGroup: String,
        bundleIdentifier: String
    ) -> String? {
        let prefix: String
        if defaultAccessGroup.hasSuffix(bundleIdentifier) {
            prefix = String(defaultAccessGroup.dropLast(bundleIdentifier.count))
        } else if let separator = defaultAccessGroup.firstIndex(of: ".") {
            prefix = String(defaultAccessGroup[...separator])
        } else {
            return nil
        }
        guard !prefix.isEmpty else { return nil }
        return prefix + SharedConstants.keychainAccessGroupSuffix
    }

    private static func readDefaultAccessGroup() -> String? {
        let account = "focusguard.access-group-probe.\(UUID().uuidString)"
        let service = "FocusGuard.AccessGroupProbe"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data([0]),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemAdd(query as CFDictionary, &result)
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ] as CFDictionary)
        }
        guard status == errSecSuccess,
              let attributes = result as? [String: Any] else {
            return nil
        }
        return attributes[kSecAttrAccessGroup as String] as? String
    }
}
