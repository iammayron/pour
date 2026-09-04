import Foundation

/// Todoist token in a 0600 file under ~/Library/Application Support/Pour.
/// Not the Keychain: its ACL cannot remember an app without an Apple-issued certificate, so every launch prompted.
/// ponytail: switch to the data-protection keychain once the app is signed with a Developer ID.
public enum TokenStore {
    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pour", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("todoist-token")
    }

    public static var token: String? {
        get {
            guard let data = try? Data(contentsOf: file), let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
            return s
        }
        set {
            guard let newValue, !newValue.isEmpty else { try? FileManager.default.removeItem(at: file); return }
            try? Data(newValue.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}
