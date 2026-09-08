import Foundation
import Security

enum EndpointKey {
    private static let service = (Bundle.main.bundleIdentifier ?? "in.sammyk.trellis") + ".endpoint"
    private static func query(_ endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: endpoint]
    }
    static func save(_ key: String, endpoint: String) throws {
        guard key.utf8.count <= 16_384, !key.utf8.contains(0), endpoint.utf8.count <= 4096 else {
            throw Failure("Invalid endpoint or key length.")
        }
        let value = Data(key.utf8)
        let status = SecItemUpdate(query(endpoint) as CFDictionary, [kSecValueData: value] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(endpoint)
            attributes[kSecValueData as String] = value
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else { try check(status) }
    }
    // Presence must not read secret bytes or trigger a Keychain access prompt while typing an endpoint.
    static func isSaved(endpoint: String) throws -> Bool {
        let status = SecItemCopyMatching(query(endpoint) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }
    static func read(endpoint: String) throws -> String {
        var attributes = query(endpoint)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        try check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw Failure("The stored API key could not be decoded.")
        }
        return value
    }
    static func remove(endpoint: String) throws {
        let status = SecItemDelete(query(endpoint) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure("Keychain operation failed (\(status)).") }
    }
    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
