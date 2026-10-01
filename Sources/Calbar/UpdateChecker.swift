import AppKit
import CalbarCore
import UserNotifications

/// Looks for newer Calbar releases on GitHub, adapted from Claudette. Uses
/// the anonymous releases API (60 requests per hour and per IP, far more
/// than needed). Two entry points:
/// - `startPeriodicCheck()`: at launch, every 24 h and on wake, at most
///   once per 24 h. Posts a notification with an "Update" action, once
///   per new version.
/// - `checkManually()`: from the settings, always asks GitHub and returns
///   the result without touching the notification state.
@MainActor
enum UpdateChecker {
    static let repoURL = URL(string: "https://github.com/emilevauge/calbar")!
    static let assetName = "Calbar.dmg"
    private static let latestAPI = URL(string: "https://api.github.com/repos/emilevauge/calbar/releases/latest")!
    private static let latestPage = URL(string: "https://github.com/emilevauge/calbar/releases/latest")!

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheckedAt"
    private static let lastNotifiedKey = "lastNotifiedUpdateVersion"

    private static let kind = "update"
    private static let categoryID = "update"
    private static let updateActionID = "update.now"
    private static let notesActionID = "update.notes"

    private static var timer: Timer?
    private static var wakeObserver: NSObjectProtocol?

    enum ManualResult {
        case upToDate(current: String)
        case newer(GitHubRelease)
        case error(String)
    }

    /// `CFBundleShortVersionString`, "dev" for a binary without bundle.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Arms the checks. Skipped without a bundle id: a dev binary has no
    /// version to compare and cannot update itself.
    static func startPeriodicCheck() {
        guard Bundle.main.bundleIdentifier != nil, timer == nil else { return }
        registerNotification()
        triggerBackgroundCheck()

        // The timer does not tick while the Mac sleeps: the wake observer
        // covers a long sleep. Both go through the same 24 h cooldown.
        let timer = Timer(timeInterval: checkInterval, repeats: true) { _ in
            MainActor.assumeIsolated { triggerBackgroundCheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { triggerBackgroundCheck() }
        }
    }

    static func checkManually() async -> ManualResult {
        do {
            let release = try await fetchLatest()
            let current = currentVersion
            return AppVersion.isNewer(release.version, than: current) ? .newer(release) : .upToDate(current: current)
        } catch {
            NSLog("Calbar: update check failed: %@", "\(error)")
            return .error("Could not reach GitHub")
        }
    }

    // MARK: private

    private static func triggerBackgroundCheck() {
        let defaults = UserDefaults.standard
        guard UpdatePolicy.shouldCheck(lastCheck: defaults.object(forKey: lastCheckKey) as? Date,
                                       now: Date(), interval: checkInterval) else { return }
        Task {
            guard let release = try? await fetchLatest() else { return }
            // Only a check that reached GitHub starts the cooldown.
            defaults.set(Date(), forKey: lastCheckKey)
            guard UpdatePolicy.shouldNotify(latest: release.version, current: currentVersion,
                                            lastNotified: defaults.string(forKey: lastNotifiedKey)) else { return }
            defaults.set(release.version, forKey: lastNotifiedKey)
            notify(release)
        }
    }

    private static func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: latestAPI, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Calbar/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try GitHubRelease.parse(data, assetName: assetName, fallbackPage: latestPage)
    }

    // MARK: notification

    private static func registerNotification() {
        let update = UNNotificationAction(identifier: updateActionID, title: "Update", options: [.foreground])
        let notes = UNNotificationAction(identifier: notesActionID, title: "Release notes", options: [.foreground])
        let category = UNNotificationCategory(identifier: categoryID, actions: [update, notes],
                                              intentIdentifiers: [], options: [])
        NotificationHub.shared.register(kind: kind, categories: [category]) { action, info in
            let page = info["pageURL"].flatMap(URL.init(string:)) ?? latestPage
            if action == updateActionID, let dmg = info["dmgURL"].flatMap(URL.init(string:)) {
                Task {
                    if let error = await SelfUpdater.run(dmgURL: dmg) { notifyFailure(error) }
                }
            } else {
                // Body click, "Release notes", or "Update" without a DMG.
                NSWorkspace.shared.open(page)
            }
        }
    }

    private static func notify(_ release: GitHubRelease) {
        let content = UNMutableNotificationContent()
        content.title = "Calbar \(release.version) is available"
        content.body = release.dmgURL == nil
            ? "Click to open the release page."
            : "Click Update to install it and relaunch Calbar."
        content.sound = .default
        content.categoryIdentifier = categoryID
        var info = ["pageURL": release.pageURL.absoluteString]
        if let dmg = release.dmgURL { info["dmgURL"] = dmg.absoluteString }
        content.userInfo = info
        NotificationHub.shared.post(kind: kind, id: "calbar.update.\(release.version)", content: content)
    }

    static func notifyFailure(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Calbar could not update"
        content.body = message
        content.sound = .default
        NotificationHub.shared.post(kind: kind, id: "calbar.update.failed", content: content)
    }
}
