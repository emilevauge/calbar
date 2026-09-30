import SwiftUI
import KeyboardShortcuts
import MacalCore

struct SettingsView: View {
    @ObservedObject private var app = AppDelegate.shared
    @ObservedObject private var accounts = AppDelegate.shared.accounts

    @AppStorage(Prefs.leadMinutesKey) private var leadMinutes = 10
    @AppStorage(Prefs.lingerMinutesKey) private var lingerMinutes = 5
    @AppStorage(Prefs.showDeclinedKey) private var showDeclined = false
    @AppStorage(Prefs.notifyBeforeMeetingsKey) private var notifyBeforeMeetings = true
    @AppStorage(Prefs.openPanelAtDayStartKey) private var openPanelAtDayStart = true
    @State private var launchAtLogin = LaunchAgent.isEnabled
    @State private var busy = false
    @State private var checkingForUpdates = false
    @State private var updateResult: UpdateChecker.ManualResult?
    @State private var updating = false
    @State private var updateError: String?
    /// Accounts whose calendar list is unfolded.
    @State private var expandedAccounts: Set<String> = []

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(accounts.accounts) { account in
                    accountRow(account)
                }
                if app.isSigningIn {
                    SignInProgress()
                } else {
                    Button("Add a Google account…") {
                        app.addAccount()
                    }
                    .disabled(busy || app.auth == nil)
                }
                if let error = app.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                oauthClientRow
            }

            Section {
                Stepper(value: $leadMinutes, in: 1...60) {
                    valueRow("Alert before", "\(leadMinutes) min")
                }
                Stepper(value: $lingerMinutes, in: 0...30) {
                    valueRow("Keep after the start", "\(lingerMinutes) min")
                }
                Toggle("Notify before a meeting", isOn: $notifyBeforeMeetings)
            } header: {
                Text("Alerts")
            } footer: {
                Text("A Join button shows in the menu bar before each meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Toggle("Show declined events", isOn: $showDeclined)
            }

            Section("Global shortcut") {
                ShortcutRecorder(title: "Open Macal", name: .toggleMacal)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue { try LaunchAgent.enable() } else { try LaunchAgent.disable() }
                        } catch {
                            launchAtLogin = LaunchAgent.isEnabled
                        }
                    }
                Toggle("Open the panel at the start of the day", isOn: $openPanelAtDayStart)
            } header: {
                Text("Startup")
            } footer: {
                Text("Once a day, from 6:00, when a meeting is still ahead today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Always last: version, updates and legal information.
            aboutSection
        }
        .formStyle(.grouped)
        // Bounded height: the grouped Form scrolls, so every calendar and
        // the sections below them stay reachable.
        .frame(width: 380, height: Self.height)
    }

    /// 560 points, less on a screen too short to show that much.
    private static var height: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return min(560, visible - 120)
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        HStack {
            Text(account.email)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            if account.needsReconnect {
                Button("Reconnect") {
                    app.addAccount(loginHint: account.email)
                }
                .foregroundStyle(.red)
            }
            Button {
                run { await app.removeAccount(account.email) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Remove this account")
        }
        // Collapsed by default: an account can have dozens of calendars.
        // A full-width row with a count, rather than a DisclosureGroup
        // triangle, so the list is easy to find.
        let expanded = expandedAccounts.contains(account.email)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expanded {
                    expandedAccounts.remove(account.email)
                } else {
                    expandedAccounts.insert(account.email)
                }
            }
        } label: {
            HStack {
                Text("Calendars")
                Spacer()
                Text("\(account.calendars.filter(\.enabled).count) of \(account.calendars.count) shown")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if expanded {
            CalendarPicker(account: account)
        }
    }

    /// The imported client, its ID shortened, never the secret.
    @ViewBuilder
    private var oauthClientRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("OAuth client")
                Text(app.auth.map { OAuthClientFile.maskedID($0.client.clientID) } ?? "None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(app.auth == nil ? "Import OAuth client…" : "Replace OAuth client…") {
                app.importOAuthClient()
            }
            .disabled(app.isSigningIn)
        }
        if let error = app.clientImportError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: about

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            valueRow("Version", UpdateChecker.currentVersion)

            HStack(spacing: 8) {
                Button("Check for updates") {
                    Task { await checkForUpdates() }
                }
                .disabled(checkingForUpdates || updating)
                if checkingForUpdates {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let updateResult, !checkingForUpdates {
                    updateResultLabel(updateResult)
                }
            }

            if case .newer(let release) = updateResult {
                HStack(spacing: 8) {
                    if let dmg = release.dmgURL {
                        Button("Update to \(release.version) now") {
                            updating = true
                            updateError = nil
                            Task {
                                // Returns only on failure: on success Macal quits.
                                updateError = await SelfUpdater.run(dmgURL: dmg)
                                updating = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updating)
                    }
                    Button("Release notes") {
                        NSWorkspace.shared.open(release.pageURL)
                    }
                    if updating {
                        ProgressView().controlSize(.small)
                    }
                }
                if let updateError {
                    Text(updateError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            valueRow("License", "MIT")
            HStack {
                Text("Source")
                Spacer()
                Link("github.com/emilevauge/macal", destination: UpdateChecker.repoURL)
                    .font(.callout)
            }
            Text("© 2026 Emile Vauge")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func updateResultLabel(_ result: UpdateChecker.ManualResult) -> some View {
        switch result {
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .newer(let release):
            Label("\(release.version) is available", systemImage: "arrow.up.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func checkForUpdates() async {
        checkingForUpdates = true
        updateResult = nil
        updateError = nil
        updateResult = await UpdateChecker.checkManually()
        checkingForUpdates = false
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task {
            await work()
            busy = false
        }
    }
}

/// Shown while the browser sign-in waits for Google.
struct SignInProgress: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Signing in…")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                AppDelegate.shared.cancelSignIn()
            }
        }
    }
}
