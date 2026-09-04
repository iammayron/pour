import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import TodoistCore

/// Todoist OAuth for a public client: no client_secret, PKCE instead.
///
/// The client_id IS the metadata document URL (docs/oauth/client.json, served by GitHub Pages).
/// Todoist demands an https redirect_uri, so that page bounces the code to pour://oauth, which
/// ASWebAuthenticationSession intercepts by scheme — no URL type in Info.plist, no app-wide handler.
enum TodoistOAuth {
    static let clientId = "https://iammayron.github.io/pour/oauth/client.json"
    static let redirectUri = "https://iammayron.github.io/pour/oauth/callback.html"
    static let scope = "data:read_write"
    private static let callbackScheme = "pour"
    private static let tokenEndpoint = URL(string: "https://todoist.com/oauth/access_token")!

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Flow

    @MainActor
    static func connect(anchor: ASPresentationAnchor? = nil) async throws -> TodoistAuth {
        let verifier = base64url(Data((0..<64).map { _ in UInt8.random(in: .min ... .max) }))
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = base64url(Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }))

        var comps = URLComponents(string: "https://todoist.com/oauth/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectUri),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callback = try await authenticate(url: comps.url!, anchor: anchor)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let err = value("error") { throw Failure(message: "Todoist denied the request: \(err)") }
        // Rejecting a mismatched state is the whole point of sending one: it blocks a code injected by someone else.
        guard value("state") == state else { throw Failure(message: "OAuth state mismatch — the response did not come from this request.") }
        guard let code = value("code") else { throw Failure(message: "Todoist returned no authorization code.") }

        return try await exchange(["grant_type": "authorization_code",
                                   "code": code,
                                   "redirect_uri": redirectUri,
                                   "code_verifier": verifier])
    }

    /// Todoist rotates the refresh token, so the result must replace the stored pair, never merge into it.
    static func refresh(_ auth: TodoistAuth) async throws -> TodoistAuth {
        guard let refreshToken = auth.refreshToken else { throw Failure(message: "This token cannot be refreshed. Reconnect Todoist.") }
        return try await exchange(["grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    // MARK: - plumbing

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    private static func exchange(_ fields: [String: String]) async throws -> TodoistAuth {
        var body = URLComponents()
        body.queryItems = (fields.merging(["client_id": clientId]) { a, _ in a }).map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure(message: "Todoist HTTP \(status): \(String(decoding: data, as: UTF8.self))")
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TodoistAuth(accessToken: t.access_token,
                           refreshToken: t.refresh_token,
                           expiresAt: t.expires_in.map { Date().addingTimeInterval($0) })
    }

    @MainActor
    private static func authenticate(url: URL, anchor: ASPresentationAnchor?) async throws -> URL {
        let presenter = Presenter(anchor: anchor)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                switch (callback, error) {
                case let (callback?, _): continuation.resume(returning: callback)
                case let (_, error?):    continuation.resume(throwing: error)
                default:                 continuation.resume(throwing: Failure(message: "The Todoist sign-in window closed without a result."))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false   // reuse the Safari login so most people never type a password
            withExtendedLifetime(presenter) {
                if !session.start() { continuation.resume(throwing: Failure(message: "Could not open the Todoist sign-in window.")) }
            }
        }
    }

    /// ASWebAuthenticationSession needs a window to hang the sheet on; Pour is LSUIElement and often has none.
    @MainActor
    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        private let anchor: ASPresentationAnchor?
        init(anchor: ASPresentationAnchor?) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor ?? NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
