import SwiftUI
import AppKit
import MacalCore

struct MenuView: View {
    @ObservedObject var store: EventStore
    @ObservedObject var accounts: AccountStore
    @ObservedObject private var app = AppDelegate.shared
    /// Bound only so the list re-renders when the setting changes.
    @AppStorage(Prefs.showDeclinedKey) private var showDeclined = false

    @State private var expandedID: String?
    @State private var selectedIndex = 0
    /// Day shown, in days from today. Back to 0 whenever the popover closes.
    @State private var dayOffset = 0
    @FocusState private var focused: Bool

    var body: some View {
        let agenda = store.agenda
        let day = DayWindow.day(offset: dayOffset, from: store.now, calendar: .current)
        // Today keeps its own presentation; other days come from the store.
        let other: DayContent? = dayOffset == 0 ? nil : store.events(for: day)
        let rows = Self.rows(agenda, other)
        let focusID = other == nil ? Self.focusID(agenda, now: store.now) : nil

        VStack(alignment: .leading, spacing: 0) {
            header(agenda, day: day, other: other)
            Divider()
            content(agenda, day: day, other: other, rows: rows, focusID: focusID)
            Divider()
            footer
        }
        .frame(width: 380)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(rows.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        // Up and down move the selection; left and right change the day.
        .onKeyPress(.leftArrow) {
            changeDay(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            changeDay(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            AppDelegate.shared.closePopover()
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            guard rows.indices.contains(selectedIndex) else { return .ignored }
            let event = rows[selectedIndex]
            if press.modifiers.contains(.command) {
                join(event)
            } else {
                toggle(event, focusID: focusID)
            }
            return .handled
        }
        .onAppear {
            focused = true
            applyRequestedEvent()
        }
        .onChange(of: app.popoverCloseCount) {
            showToday()
        }
        .onChange(of: store.requestedEventID) {
            applyRequestedEvent()
        }
    }

    // MARK: header

    private func header(_ agenda: DayAgenda, day: Date, other: DayContent?) -> some View {
        DayHeader(day: day, isToday: other == nil, onChange: changeDay(by:), onToday: showToday) {
            if let other {
                DayHeader.otherDayInfo(other, offset: dayOffset)
            } else if store.isOffline, let last = store.lastFetch {
                Label("offline · updated \(AgendaFormat.duration(store.now.timeIntervalSince(last))) ago",
                      systemImage: "wifi.slash")
            } else if !agenda.current.isEmpty {
                Text(agenda.current.count == 1 ? "1 left" : "\(agenda.current.count) left")
            }
        }
    }

    // MARK: content

    /// Rows reachable with the arrow keys, in display order.
    static func rows(_ agenda: DayAgenda, _ other: DayContent?) -> [CalendarEvent] {
        switch other {
        case nil: agenda.current + agenda.past
        case .loaded(let listing): listing.timed
        case .loading, .failed: []
        }
    }

    @ViewBuilder
    private func content(
        _ agenda: DayAgenda, day: Date, other: DayContent?, rows: [CalendarEvent], focusID: String?
    ) -> some View {
        if app.auth == nil {
            OAuthClientSetup()
        } else if accounts.accounts.isEmpty {
            VStack(spacing: 10) {
                Text("No Google account connected")
                    .foregroundStyle(.secondary)
                if app.isSigningIn {
                    SignInProgress()
                        .fixedSize()
                } else {
                    Button("Connect a Google account") {
                        app.addAccount()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let error = app.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if let other {
                            otherDayList(other, day: day)
                        } else {
                            todayList(agenda, rows: rows, focusID: focusID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // A new day starts scrolled to the top.
                .id(day)
                .frame(maxHeight: 560)
                .onChange(of: selectedIndex) { _, index in
                    guard rows.indices.contains(index) else { return }
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(rows[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func todayList(_ agenda: DayAgenda, rows: [CalendarEvent], focusID: String?) -> some View {
        // All-day events stay on top, above "Nothing
        // left today" once the timed ones are over.
        if !agenda.allDay.isEmpty {
            AllDayStrip(events: agenda.allDay)
        }
        if store.isLoading {
            LoadingRow()
        } else if agenda.current.isEmpty {
            endOfDay(agenda.firstTomorrow)
        }
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
            if index == agenda.current.count && !agenda.past.isEmpty {
                sectionHeader("Ended")
            }
            EventRow(
                event: event,
                now: store.now,
                selected: index == selectedIndex,
                expanded: event.id == focusID || expandedID == event.id,
                isPast: index >= agenda.current.count,
                onToggle: {
                    // The focused meeting stays open; clicking it does nothing.
                    guard event.id != focusID else { return }
                    selectedIndex = index
                    toggle(event, focusID: focusID)
                },
                onJoin: { join(event) }
            )
            .id(event.id)
        }
    }

    private func otherDayList(_ content: DayContent, day: Date) -> some View {
        DayList(
            content: content, now: store.now, selectedIndex: selectedIndex, expandedID: expandedID,
            onToggle: { index, event in
                selectedIndex = index
                toggle(event, focusID: nil)
            },
            onJoin: join,
            onRetry: { store.retry(day) }
        )
    }

    private func endOfDay(_ next: CalendarEvent?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing left today")
                .font(.body.weight(.medium))
            if let next {
                Text("Tomorrow \(AgendaFormat.clock(next.start, .current)) · \(next.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            VStack { Divider() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: footer

    private var footer: some View {
        MenuFooter(isRefreshing: store.isRefreshing, onRefresh: {
            Task { await store.refresh() }
        }, calendarURL: GoogleCalendarWeb.home(authuser: accounts.accounts.first?.email)) {
            SettingsView()
        }
    }

    // MARK: actions

    /// Meeting always shown expanded: the ongoing one, otherwise the next one.
    static func focusID(_ agenda: DayAgenda, now: Date) -> String? {
        NextMeeting.focus(events: agenda.current, now: now, calendar: .current)?.id
    }

    /// Expands or collapses `event`. The focused meeting cannot be collapsed.
    private func toggle(_ event: CalendarEvent, focusID: String?) {
        guard event.id != focusID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            expandedID = expandedID == event.id ? nil : event.id
        }
    }

    private func changeDay(by delta: Int) {
        dayOffset += delta
        expandedID = nil
        selectedIndex = 0
    }

    private func showToday() {
        guard dayOffset != 0 else { return }
        changeDay(by: -dayOffset)
    }

    private func join(_ event: CalendarEvent) {
        guard let link = event.meeting else { return }
        AppDelegate.shared.closePopover()
        MeetingOpener.open(link)
    }

    private func applyRequestedEvent() {
        guard let id = store.requestedEventID else { return }
        store.requestedEventID = nil
        // The requested meeting is today's.
        showToday()
        expandedID = id
        let rows = Self.rows(store.agenda, nil)
        if let index = rows.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }
}

/// Empty state until a Google OAuth client is imported: Macal ships
/// without one, each user brings their own.
private struct OAuthClientSetup: View {
    @ObservedObject private var app = AppDelegate.shared

    static let helpURL = URL(string: "https://github.com/emilevauge/macal#google-oauth-client")!

    var body: some View {
        VStack(spacing: 10) {
            Text("Macal needs a Google OAuth client")
                .font(.body.weight(.medium))
            Text("Create a Desktop app client in Google Cloud Console, download its JSON file, then import it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Import google-oauth.json…") {
                app.importOAuthClient()
            }
            .buttonStyle(.borderedProminent)
            Link("How to create one", destination: Self.helpURL)
                .font(.caption)
            if let error = app.clientImportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}
