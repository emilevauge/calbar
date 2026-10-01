import Foundation

/// Where Calbar finds the Google OAuth client, and how the app shows it.
///
/// The client is never shipped in the release bundle: the user imports
/// the JSON file Google Cloud Console downloads, and Calbar keeps a copy in
/// its Application Support folder. Dev builds may still carry one as a
/// SwiftPM resource, used only when nothing was imported.
public enum OAuthClientFile {
    public static let fileName = "google-oauth.json"

    /// The client ID or secret is empty.
    public struct InvalidClient: Error, Equatable {}

    /// `<Application Support>/Calbar/google-oauth.json`.
    public static func importedURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Calbar", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// The imported client when there is one, otherwise the bundled one
    /// when present, otherwise `nil`.
    public static func choose(imported: URL, bundled: URL?, fileExists: (URL) -> Bool) -> URL? {
        if fileExists(imported) { return imported }
        if let bundled, fileExists(bundled) { return bundled }
        return nil
    }

    /// Enough of the client ID to tell two clients apart:
    /// "4840…apps.googleusercontent.com".
    public static func maskedID(_ id: String) -> String {
        let googleSuffix = "apps.googleusercontent.com"
        if id.hasSuffix("." + googleSuffix), id.count > googleSuffix.count + 5 {
            return "\(id.prefix(4))…\(googleSuffix)"
        }
        guard id.count > 12 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }

    /// Refresh tokens belong to the client that issued them: accounts
    /// signed in with another client must sign in again. An unknown
    /// previous client (nothing recorded yet) counts as the same one.
    public static func accountsMustReconnect(knownClientID: String?, newClientID: String, hasAccounts: Bool) -> Bool {
        guard hasAccounts, let knownClientID else { return false }
        return knownClientID != newClientID
    }
}
