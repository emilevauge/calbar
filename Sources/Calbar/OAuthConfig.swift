import Foundation
import CalbarCore

/// The Google OAuth client. The release bundle never contains one: the
/// user imports the JSON file of their own "Desktop app" client, copied to
/// `~/Library/Application Support/Calbar/google-oauth.json`. A dev build
/// also finds `Resources/google-oauth.json` in its SwiftPM resource bundle,
/// used only when nothing was imported.
enum OAuthConfig {
    /// Client ID of the client last loaded or imported, to notice a change.
    private static let knownClientIDKey = "oauthClientID"

    static var importedURL: URL {
        OAuthClientFile.importedURL(
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        )
    }

    /// `google-oauth.json` in the `Calbar_Calbar.bundle` next to the dev
    /// binary. Looked up by hand rather than with `Bundle.module`, whose
    /// accessor aborts the process when the resource bundle is missing, as
    /// it is in the release app.
    static var bundledURL: URL? {
        let folders = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for folder in folders {
            guard let bundle = Bundle(url: folder.appendingPathComponent("Calbar_Calbar.bundle")) else { continue }
            if let url = bundle.url(forResource: "google-oauth", withExtension: "json") { return url }
        }
        return nil
    }

    /// The imported client, else the bundled one, `nil` when there is none
    /// or the file is invalid.
    static func load() -> OAuthClient? {
        guard let url = OAuthClientFile.choose(
            imported: importedURL, bundled: bundledURL,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        ) else { return nil }
        do {
            return try OAuthClient.load(json: Data(contentsOf: url))
        } catch {
            NSLog("Calbar: invalid OAuth client file %@", url.lastPathComponent)
            return nil
        }
    }

    /// Validates the file at `source`, then copies it to `importedURL`,
    /// readable by the user only. Nothing is written when it is invalid.
    static func importFile(at source: URL) throws -> OAuthClient {
        let data = try Data(contentsOf: source)
        let client = try OAuthClient.load(json: data)
        let destination = importedURL
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written under a temporary name with 0600 from the start, then
        // swapped in, so the secret is never readable by other users.
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(OAuthClientFile.fileName).\(UUID().uuidString)")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fm.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return client
    }

    static var knownClientID: String? {
        get { UserDefaults.standard.string(forKey: knownClientIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: knownClientIDKey) }
    }
}
