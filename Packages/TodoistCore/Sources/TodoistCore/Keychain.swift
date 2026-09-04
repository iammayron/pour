import Foundation
import Security

/// One generic-password item. ponytail: single account; multi-account needs a per-account key.
public enum Keychain {
    private static let service = "com.mayron.todoist-floating"
    private static let account = "todoist-token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static var token: String? {
        get {
            var q = query
            q[kSecReturnData as String] = true
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var q = query
            q[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
