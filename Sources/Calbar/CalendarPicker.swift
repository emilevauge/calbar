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
                    }
                }
            }
        }
    }
}
