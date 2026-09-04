import Foundation
import Testing
@testable import TodoistCore

// Disk is deliberately untouched: these cover the encode/decode pair only, so running the
// suite can never overwrite the real ~/Library/Application Support/Pour/todoist-token.
struct TokenStoreTests {
    @Test func readsPreOAuthBareToken() {
        let a = TodoistAuth.decode(Data("0123456789abcdef".utf8))
        #expect(a?.accessToken == "0123456789abcdef")
        #expect(a?.isOAuth == false)
        #expect(a?.isExpired == false)   // a pasted token never expires
    }

    @Test func trimsTrailingNewlineFromAHandEditedFile() {
        #expect(TodoistAuth.decode(Data("abc\n".utf8))?.accessToken == "abc")
    }

    @Test func emptyOrBlankFileIsNoCredentials() {
        #expect(TodoistAuth.decode(Data()) == nil)
        #expect(TodoistAuth.decode(Data("  \n".utf8)) == nil)
    }

    @Test func oAuthPairSurvivesARoundTrip() {
        let due = Date().addingTimeInterval(3600)
        let a = TodoistAuth(accessToken: "at", refreshToken: "rt", expiresAt: due)
        let back = TodoistAuth.decode(a.encoded())
        #expect(back?.accessToken == "at")
        #expect(back?.refreshToken == "rt")          // losing this locks the user out on next refresh
        #expect(back?.isOAuth == true)
        #expect(abs((back?.expiresAt ?? .distantPast).timeIntervalSince(due)) < 1)
    }

    @Test func bareTokenIsWrittenBackAsAStringNotJSON() {
        #expect(TodoistAuth(accessToken: "plain").encoded() == Data("plain".utf8))
    }

    @Test func expiryHasSlackSoATokenIsNotUsedMidFlight() {
        #expect(TodoistAuth(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(30)).isExpired)
        #expect(!TodoistAuth(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(600)).isExpired)
    }
}
