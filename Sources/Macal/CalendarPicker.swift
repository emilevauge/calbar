import SwiftUI
import MacalCore

/// On/off toggles for the calendars of one account, in the settings
/// panel. Turning a calendar on refetches, since its events were never
/// downloaded.
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
                    }
                }
            }
        }
    }
}
