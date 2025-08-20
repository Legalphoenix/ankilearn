import Foundation
import Security

enum Keychain {
    private static let service = "MnemonicMaker"
    private static let account = "OpenAI_API_Key"

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)

        // Delete old if exists
        let queryDelete: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(queryDelete as CFDictionary)

        // Add new
        let queryAdd: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(queryAdd as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to save API key (\(status))"])
        }
    }

    static func loadAPIKey() -> String? {
        let query: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return str
        }
        return nil
    }
}
