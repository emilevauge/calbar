import SwiftUI
import CalbarCore

/// On/off toggles for the calendars of one account, in the settings
/// panel, and a bell for its alerts. Turning a calendar on refetches,
/// since its events were never downloaded.
struct CalendarPicker: View {
    let account: Account

    var body: some View {
        if account.calendars.isEmpty {
            Text("No calendars loaded")
                .foregroundStyle(.secondary)
        } else {
            ForEach(account.calendars) { calendar in
                Toggle(isOn: Binding(
                    get: { calendar.enabled },
                    set: { enabled in
                        let app = AppDelegate.shared
                        app.accounts.setEnabled(enabled, calendarID: calendar.id, email: account.email)
                        Task { await app.store.refresh() }
                    }
                )) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: calendar.colorHex))
                            .frame(width: 8, height: 8)
                        Text(calendar.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            AppDelegate.shared.accounts.setAlerts(!calendar.alertsOn, calendarID: calendar.id,
                                                                  email: account.email)
                        } label: {
                            Image(systemName: calendar.alertsOn ? "bell.fill" : "bell.slash")
                                .foregroundStyle(calendar.alertsOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                                .frame(width: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!calendar.enabled)
                        .help(calendar.alertsOn
                              ? "Alerts on: countdown in the icon, notifications and peeks. Click to turn off."
                              : "Alerts off: shown, but never counted down or notified. Click to turn on.")
                        if calendar.isAdded == true {
                            Button {
                                AppDelegate.shared.accounts.removeCalendar(calendar.id, email: account.email)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Remove this colleague's calendar")
                        }
                    }
                }
            }
        }
    }
}

/// From the panel's footer: every account's calendars, to show, mute or
/// remove, and a colleague's calendar to add by email.
struct CalendarsPanel: View {
    @ObservedObject var accounts = AppDelegate.shared.accounts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(accounts.accounts) { account in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account.email)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        CalendarPicker(account: account)
                        ColleagueField(account: account.email)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 320)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A colleague's email, added on return once Google lets the account read
/// that calendar.
private struct ColleagueField: View {
    let account: String
    @State private var email = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.secondary)
                TextField("Add a colleague's calendar (email)", text: $email)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
                if busy { ProgressView().controlSize(.mini) }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .font(.system(size: 12))
        .padding(.top, 2)
    }

    private func add() {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !busy, NewEvent.guests(from: address).count == 1 else {
            error = address.isEmpty ? nil : "Type an email address."
            return
        }
        let app = AppDelegate.shared
        let name = app.contacts.index.search(address).first { $0.email.lowercased() == address.lowercased() }?.name
        busy = true
        error = nil
        Task {
            do {
                try await app.store.addColleague(address, name: name, to: account)
                email = ""
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? describe(error)
            }
            busy = false
        }
    }
}
