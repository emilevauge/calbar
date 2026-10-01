import AppKit
import CalbarCore
import Security

/// The app was called Macal up to 0.2.9 (bundle id `dev.macal.app`). This
/// moves what Macal left on the Mac over to Calbar, once:
/// - `relocateIfNeeded`: the Macal updater installs the transition release
///   as `Macal.app`; launched from there, Calbar copies itself to a sibling
///   `Calbar.app`, starts that copy and quits.
/// - `migrate`: settings, Google refresh tokens, the OAuth client file and
///   the event cache, and the login item. Macal's own data is left in
///   place, so going back to Macal still works.
/// - `trashOldApp`: moves a `Macal.app` next to Calbar to the Trash.
enum LegacyMacal {
    static let bundleID = "dev.macal.app"
    static let appName = "Macal.app"
    private static let keychainService = "dev.macal.app.google-refresh-token"
    private static let migratedKey = "migratedFromMacal"

    // MARK: relocation

    /// True when this process started a copy of itself and must exit.
    static func relocateIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.lastPathComponent == appName else { return false }
        let target = bundle.deletingLastPathComponent().appendingPathComponent("Calbar.app")
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: bundle, to: target)
        } catch {
            NSLog("Calbar: could not copy itself to %@: %@", target.path, "\(error)")
            return false
        }
        // Start the copy once this process is gone: it would otherwise see
        // a running instance with the same bundle id and quit.
        let quoted = SelfUpdateScript.quote(target.path)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; xattr -dr com.apple.quarantine \(quoted) 2>/dev/null; open \(quoted)"]
        do {
            try task.run()
        } catch {
            NSLog("Calbar: could not start %@: %@", target.path, "\(error)")
            return false
        }
        NSLog("Calbar: relocated from %@ to %@", bundle.path, target.path)
        return true
    }

    // MARK: migration

    /// Runs before the stores read their data.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }
        guard let old = defaults.persistentDomain(forName: bundleID), !old.isEmpty else { return }
        NSLog("Calbar: migrating from Macal")

        // Two apps would fight over the menu bar and the login item.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }

        migrateDefaults(old, into: defaults)
        migrateTokens(accountsData: old["accounts"] as? Data)
        migrateFiles()
        migrateLoginItem()
    }

    private static func migrateDefaults(_ old: [String: Any], into defaults: UserDefaults) {
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        // The global shortcut is stored under its name, which changed.
        if let shortcut = old["KeyboardShortcuts_toggleMacal"],
           defaults.object(forKey: "KeyboardShortcuts_toggleCalbar") == nil {
            defaults.set(shortcut, forKey: "KeyboardShortcuts_toggleCalbar")
        }
        defaults.removeObject(forKey: "KeyboardShortcuts_toggleMacal")
    }

    /// One item per account, read under Macal's service name. macOS asks
    /// once per item whether Calbar may read Macal's item.
    private static func migrateTokens(accountsData: Data?) {
        guard let accountsData,
              let accounts = try? JSONDecoder().decode([Account].self, from: accountsData) else { return }
        for account in accounts {
            guard (try? Keychain.read(account: account.email)) ?? nil == nil else { continue }
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account.email,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            query.removeAll()
            guard status == errSecSuccess, let data = item as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                NSLog("Calbar: no Macal token for an account (%d)", status)
                continue
            }
            do {
                try Keychain.save(token, account: account.email)
            } catch {
                NSLog("Calbar: could not save a migrated token: %@", "\(error)")
            }
        }
    }

    /// The imported OAuth client and the event cache.
    private static func migrateFiles() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("Macal", isDirectory: true)
        let new = support.appendingPathComponent("Calbar", isDirectory: true)
        guard fm.fileExists(atPath: old.path) else { return }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for name in ["google-oauth.json", "events.json"] {
            let from = old.appendingPathComponent(name)
            let to = new.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            do {
                try fm.copyItem(at: from, to: to)
                // The OAuth client holds a secret: owner only, like an import.
                if name == "google-oauth.json" {
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: to.path)
                }
            } catch {
                NSLog("Calbar: could not copy %@: %@", name, "\(error)")
            }
        }
    }

    /// Replaces Macal's LaunchAgent with Calbar's when it was on.
    private static func migrateLoginItem() {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
        guard FileManager.default.fileExists(atPath: plist.path) else { return }
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", "-w", plist.path]
        try? unload.run()
        unload.waitUntilExit()
        try? FileManager.default.removeItem(at: plist)
        do {
            try LaunchAgent.enable()
        } catch {
            NSLog("Calbar: could not enable the login item: %@", "\(error)")
        }
    }

    // MARK: old app

    /// A `Macal.app` next to this bundle, Macal itself or the transition
    /// copy: to the Trash, where it can still be restored.
    static func trashOldApp() {
        let old = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(appName)
        guard old != Bundle.main.bundleURL,
              let id = Bundle(url: old)?.bundleIdentifier,
              id == bundleID || id == Bundle.main.bundleIdentifier else { return }
        NSWorkspace.shared.recycle([old]) { _, error in
            if let error { NSLog("Calbar: could not trash %@: %@", old.path, "\(error)") }
        }
    }
}
