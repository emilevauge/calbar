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
                            .help("Remove this calendar")
                        }
                    }
                }
            }
        }
    }
}

/// From the panel's footer: a field on top to add someone's calendar,
/// then every account's calendars, to show, mute or remove.
struct CalendarsPanel: View {
    @ObservedObject var accounts = AppDelegate.shared.accounts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddCalendarField(accounts: accounts.accounts.map(\.email))
                .padding(14)
                // Its suggestions float over the list below.
                .zIndex(1)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(accounts.accounts) { account in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(account.email)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            CalendarPicker(account: account)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 320)
        // Room for the six floating suggestions, however few calendars.
        .frame(minHeight: 300, maxHeight: 460, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Someone, picked as a guest is in the editor (people met, Google
/// contacts and directory), whose calendar is added once Google lets an
/// account read it: the account of the same domain, else the first one.
private struct AddCalendarField: View {
    let accounts: [String]
    @ObservedObject private var contacts = AppDelegate.shared.contacts
    @State private var picked: [ContactIndex.Contact] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.secondary)
                if busy {
                    ProgressView().controlSize(.mini)
                    Text("Adding \(picked.first?.name ?? picked.first?.email ?? "")…").foregroundStyle(.secondary)
                } else {
                    GuestField(guests: $picked, contacts: contacts, placeholder: "Add someone's calendar", floating: true)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .font(.system(size: 12))
        .onAppear { contacts.prepare() }
        .onChange(of: picked) { _, new in
            if let person = new.first { add(person) }
        }
    }

    private func add(_ person: ContactIndex.Contact) {
        let domain = { (email: String) in email.split(separator: "@").last.map { $0.lowercased() } }
        guard !busy, let account = accounts.first(where: { domain($0) == domain(person.email) }) ?? accounts.first else {
            picked = []
            return
        }
        busy = true
        error = nil
        Task {
            do {
                try await AppDelegate.shared.store.addSharedCalendar(person.email, name: person.name, to: account)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? describe(error)
            }
            picked = []
            busy = false
        }
    }
}
