import Foundation

/// A personal API token, or an OAuth token pair. `expiresAt` and `refreshToken` are nil for a pasted token.
public struct TodoistAuth: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }

    /// True with a minute of slack, so a request is not fired with a token about to die mid-flight.
    public var isExpired: Bool { expiresAt.map { $0.timeIntervalSinceNow < 60 } ?? false }
    public var isOAuth: Bool { refreshToken != nil }

    /// JSON for an OAuth pair, a bare string for a pasted token, so pre-OAuth files still decode.
    public static func decode(_ data: Data) -> TodoistAuth? {
        guard !data.isEmpty else { return nil }
        if let a = try? JSONDecoder().decode(TodoistAuth.self, from: data), !a.accessToken.isEmpty { return a }
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return TodoistAuth(accessToken: s)
    }

    /// A pasted token stays a bare string, so downgrading to an older Pour still reads it.
    public func encoded() -> Data {
        isOAuth ? (try? JSONEncoder().encode(self)) ?? Data() : Data(accessToken.utf8)
    }
}

/// Todoist credentials in a 0600 file under ~/Library/Application Support/Pour.
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

    /// The file holds JSON for an OAuth pair and a bare token otherwise, so pre-OAuth installs keep working.
    public static var auth: TodoistAuth? {
        get {
            guard let data = try? Data(contentsOf: file) else { return nil }
            return TodoistAuth.decode(data)
        }
        set {
            guard let newValue, !newValue.accessToken.isEmpty else { try? FileManager.default.removeItem(at: file); return }
            try? newValue.encoded().write(to: file, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    public static var token: String? {
        get { auth?.accessToken }
        set { auth = newValue.map { TodoistAuth(accessToken: $0) } }
    }
}
