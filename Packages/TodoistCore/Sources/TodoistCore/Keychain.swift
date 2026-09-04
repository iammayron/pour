import Foundation
import Security

/// Token storage. The token lives in a 0600 file under Application Support.
///
/// Why not the Keychain: the legacy keychain ACL only remembers "Always Allow" for apps signed by an
/// Apple-issued certificate. Pour ships without a Developer ID, so users were prompted on every launch.
/// ponytail: move back to the data-protection keychain once the app has a real team / entitlements.
public enum Keychain {
    private static let service = "com.mayron.pour"
    private static let account = "todoist-token"

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pour", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("todoist-token")
    }

    public static var token: String? {
        get {
            if let data = try? Data(contentsOf: file), let s = String(data: data, encoding: .utf8), !s.isEmpty { return s }
            // One-time migration from the keychain item older builds created.
            guard let legacy = legacyKeychainToken else { return nil }
            token = legacy
            SecItemDelete(legacyQuery as CFDictionary)
            return legacy
        }
        set {
            guard let newValue, !newValue.isEmpty else { try? FileManager.default.removeItem(at: file); return }
            try? Data(newValue.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private static var legacyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static var legacyKeychainToken: String? {
        var q = legacyQuery
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
