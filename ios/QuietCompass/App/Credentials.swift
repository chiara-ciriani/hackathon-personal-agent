import Foundation
import Security

/// Server token stays in this device's Keychain, never in the app bundle or outbox.
enum Credentials {
    static let service = "com.quietcompass.server"
    static func read() throws -> String {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: "api-token", kSecReturnData: true] as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return value
    }
    static func save(_ token: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                     kSecAttrAccount: "api-token"] as CFDictionary
        let attributes = [kSecValueData: Data(token.utf8),
                          kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary
        var status = SecItemUpdate(query, attributes)
        if status == errSecItemNotFound {
            status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                kSecAttrAccount: "api-token", kSecValueData: Data(token.utf8),
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
