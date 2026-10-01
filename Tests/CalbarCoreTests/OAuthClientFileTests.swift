import Foundation
import Testing
@testable import CalbarCore

@Suite struct OAuthClientFileTests {
    let imported = URL(fileURLWithPath: "/Users/me/Library/Application Support/Calbar/google-oauth.json")
    let bundled = URL(fileURLWithPath: "/dev/.build/debug/Calbar_Calbar.bundle/google-oauth.json")

    @Test func importedURLIsInCalbarSupportFolder() {
        let support = URL(fileURLWithPath: "/Users/me/Library/Application Support")
        #expect(OAuthClientFile.importedURL(applicationSupport: support) == imported)
    }

    @Test func importedClientWins() {
        let chosen = OAuthClientFile.choose(imported: imported, bundled: bundled) { _ in true }
        #expect(chosen == imported)
    }

    @Test func bundledClientIsTheFallback() {
        let chosen = OAuthClientFile.choose(imported: imported, bundled: bundled) { $0 == bundled }
        #expect(chosen == bundled)
    }

    @Test func noClientWithoutEitherFile() {
        #expect(OAuthClientFile.choose(imported: imported, bundled: nil) { _ in false } == nil)
        #expect(OAuthClientFile.choose(imported: imported, bundled: bundled) { _ in false } == nil)
    }

    @Test func masksGoogleClientID() {
        #expect(OAuthClientFile.maskedID("484012345678-abcdefghijklmnop.apps.googleusercontent.com")
                == "4840…apps.googleusercontent.com")
    }

    @Test func masksOtherLongIDs() {
        #expect(OAuthClientFile.maskedID("abcdefghijklmnopqrstuvwxyz") == "abcd…wxyz")
    }

    @Test func keepsShortIDs() {
        #expect(OAuthClientFile.maskedID("short-id") == "short-id")
    }

    @Test func reconnectOnlyWhenTheClientChanged() {
        #expect(OAuthClientFile.accountsMustReconnect(knownClientID: "a", newClientID: "b", hasAccounts: true))
        #expect(!OAuthClientFile.accountsMustReconnect(knownClientID: "a", newClientID: "a", hasAccounts: true))
        #expect(!OAuthClientFile.accountsMustReconnect(knownClientID: "a", newClientID: "b", hasAccounts: false))
        // Unknown previous client: the accounts are assumed to use this one.
        #expect(!OAuthClientFile.accountsMustReconnect(knownClientID: nil, newClientID: "b", hasAccounts: true))
    }

    @Test func rejectsWebClientJSON() {
        let json = #"{"web": {"client_id": "id.apps.googleusercontent.com", "client_secret": "s"}}"#
        #expect(throws: (any Error).self) { try OAuthClient.load(json: Data(json.utf8)) }
    }

    @Test func descriptionHidesTheSecret() {
        let client = OAuthClient(clientID: "id", clientSecret: "GOCSPX-secret")
        #expect(!"\(client)".contains("GOCSPX"))
        #expect(!String(reflecting: client).contains("GOCSPX"))
    }

    @Test func rejectsEmptyCredentials() {
        let json = #"{"installed": {"client_id": "", "client_secret": ""}}"#
        #expect(throws: OAuthClientFile.InvalidClient.self) { try OAuthClient.load(json: Data(json.utf8)) }
    }
}
