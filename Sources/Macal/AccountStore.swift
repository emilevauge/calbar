import Foundation
import MacalCore

/// Connected Google accounts and their calendars, persisted in UserDefaults.
/// Tokens are not here, they live in the Keychain.
@MainActor
final class AccountStore: ObservableObject {
    private static let defaultsKey = "accounts"
    /// Set once saved accounts were moved to the "primary calendar only"
    /// default.
    private static let calendarDefaultsV2Key = "calendarDefaultsV2"

    @Published private(set) var accounts: [Account] = [] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        migrateCalendarDefaults()
    }

    /// One-time reset of the choices made under the old default, which
    /// enabled every calendar checked in the Google web UI: only each
    /// account's primary calendar stays on. The user turns the others back
    /// on in the settings.
    private func migrateCalendarDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.calendarDefaultsV2Key) else { return }
        accounts = accounts.map { account in
            var account = account
            account.calendars = account.calendars.map { calendar in
                var calendar = calendar
                calendar.enabled = calendar.isPrimary
                return calendar
            }
            return account
        }
        defaults.set(true, forKey: Self.calendarDefaultsV2Key)
    }

    var needsAttention: Bool {
        accounts.contains(where: \.needsReconnect)
    }

    func account(_ email: String) -> Account? {
        accounts.first { $0.email == email }
    }

    func isEnabled(calendarID: String, email: String) -> Bool {
        account(email)?.calendars.first { $0.id == calendarID }?.enabled ?? false
    }

    func upsert(email: String, grantedScopes: [String]?) {
        if let i = index(email) {
            accounts[i].needsReconnect = false
            if let grantedScopes { accounts[i].grantedScopes = grantedScopes }
        } else {
            accounts.append(Account(email: email, calendars: [], needsReconnect: false, grantedScopes: grantedScopes))
        }
    }

    /// The account may answer invitations. Unknown accounts may not.
    func canReply(_ email: String) -> Bool {
        account(email)?.canReply ?? false
    }

    func setGrantedScopes(_ scopes: [String], email: String) {
        guard let i = index(email), accounts[i].grantedScopes != scopes else { return }
        accounts[i].grantedScopes = scopes
    }

    /// Google refused an answer for lack of scope: "Reconnect to reply"
    /// until the user signs in again.
    func markReadOnly(_ email: String) {
        guard let i = index(email), accounts[i].canReply else { return }
        accounts[i].markReadOnly()
    }

    func remove(_ email: String) {
        accounts.removeAll { $0.email == email }
    }

    func setCalendars(_ fresh: [CalendarInfo], for email: String) {
        guard let i = index(email) else { return }
        let merged = CalendarInfo.merge(fresh: fresh, previous: accounts[i].calendars)
        if merged != accounts[i].calendars { accounts[i].calendars = merged }
    }

    func setEnabled(_ enabled: Bool, calendarID: String, email: String) {
        guard let i = index(email),
              let j = accounts[i].calendars.firstIndex(where: { $0.id == calendarID }) else { return }
        accounts[i].calendars[j].enabled = enabled
    }

    func setNeedsReconnect(_ value: Bool, email: String) {
        guard let i = index(email), accounts[i].needsReconnect != value else { return }
        accounts[i].needsReconnect = value
    }

    private func index(_ email: String) -> Int? {
        accounts.firstIndex { $0.email == email }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: Self.defaultsKey)
    }
}
