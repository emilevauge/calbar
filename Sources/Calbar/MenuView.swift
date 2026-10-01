import SwiftUI
import AppKit
import CalbarCore

struct MenuView: View {
    @ObservedObject var store: EventStore
    @ObservedObject var accounts: AccountStore
    @ObservedObject private var app = AppDelegate.shared
    /// Bound only so the list re-renders when the setting changes.
    @AppStorage(Prefs.showDeclinedKey) private var showDeclined = false
    @AppStorage(Prefs.viewModeKey) private var viewMode: ViewMode = .day
    @AppStorage(Prefs.weekStartHourKey) private var weekStartHour = 9
    @AppStorage(Prefs.weekEndHourKey) private var weekEndHour = 19
    @AppStorage(Prefs.weekDaysKey) private var weekDaysSetting = "1234567"

    @State private var expandedID: String?
    @State private var selectedIndex = 0
    /// Day shown, in days from today. Back to 0 whenever the popover closes.
    @State private var dayOffset = 0
    /// Today's ended events, folded by default. Folded again on close.
    @State private var showEnded = false
    @FocusState private var focused: Bool

    var body: some View {
        let agenda = store.agenda
        let day = DayWindow.day(offset: dayOffset, from: store.now, calendar: .current)
        // Today keeps its own presentation; other days come from the store.
        let other: DayContent? = dayOffset == 0 ? nil : store.events(for: day)
        let rows = Self.rows(agenda, other, showEnded: showEnded)
        // A peek is this same panel with everything but one meeting's card
        // hidden: expanding it brings the rest in around the card, which
        // keeps its identity and slides into place.
        let peeking = app.isPeeking
        let peekID = peeking ? app.peekEvent(now: store.now)?.id : nil
        let focusID = peeking ? peekID : (other == nil ? Self.focusID(agenda, now: store.now) : nil)

        let week = viewMode == .week && !peeking
        let dayGrid = viewMode == .dayGrid && !peeking

        VStack(alignment: .leading, spacing: 0) {
            if week {
                weekHeader(day: day)
                Divider()
                weekContent(day: day)
                Divider()
                footer
            } else if dayGrid {
                header(agenda, day: day, other: other)
                Divider()
                dayGridContent(day: day)
                Divider()
                footer
            } else {
                dayLayout(agenda, day: day, other: other, rows: rows, focusID: focusID, peekID: peekID, peeking: peeking)
            }
        }
        // In a peek, a click anywhere but on the card's buttons expands it.
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { app.expandPeek() }, including: peeking ? .all : .subviews)
        .frame(width: week ? WeekView.width : 380)
        // Pinned to the top: while the popover grows or shrinks around a
        // change of content, the content stays put under the arrow
        // instead of sliding to the middle.
        .frame(maxHeight: .infinity, alignment: .top)
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
        // Up and down move the selection; left and right change the day,
        // or the week in the week view.
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        // ⌫ deletes the selected event, ⌘Z brings back the last deleted.
        // macOS sends backspace as DEL (U+007F), which `.delete` (U+0008)
        // does not match: test the characters.
        .onKeyPress { press in
            guard Self.isDeleteKey(press), !week, !dayGrid, rows.indices.contains(selectedIndex) else { return .ignored }
            let event = rows[selectedIndex]
            guard store.canDelete(event) else { NSSound.beep(); return .handled }
            withAnimation(Motion.resize) { store.delete(event) }
            selectedIndex = min(selectedIndex, max(rows.count - 2, 0))
            return .handled
        }
        .onKeyPress(characters: ["z"]) { press in
            guard press.modifiers.contains(.command), store.lastDeleted != nil else { return .ignored }
            withAnimation(Motion.resize) { store.undoDelete() }
            return .handled
        }
        .onKeyPress(.escape) {
            AppDelegate.shared.closePopover()
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            guard !week, !dayGrid, rows.indices.contains(selectedIndex) else { return .ignored }
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
            showEnded = false
        }
        .onChange(of: store.requestedEventID) {
            applyRequestedEvent()
        }
    }

    @ViewBuilder
    private func dayLayout(_ agenda: DayAgenda, day: Date, other: DayContent?, rows: [CalendarEvent],
                           focusID: String?, peekID: String?, peeking: Bool) -> some View {
        if !peeking {
            header(agenda, day: day, other: other)
            Divider()
        } else if accounts.needsAttention {
            Label("An account needs to be reconnected", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        content(agenda, day: day, other: other, rows: rows, focusID: focusID, peekID: peeking ? .some(peekID) : nil)
        if peeking {
            peekHint
        } else {
            Divider()
            footer
        }
    }

    // MARK: week

    private func weekDays(_ day: Date) -> [Date] {
        WeekLayout.days(containing: day, calendar: .current, shown: WeekLayout.weekdays(weekDaysSetting))
    }

    private func weekHeader(day: Date) -> some View {
        let days = weekDays(day)
        let thisWeek = weekDays(store.now).first
        let weeks = thisWeek.flatMap { start in
            days.first.map { Calendar.current.dateComponents([.weekOfYear], from: start, to: $0).weekOfYear ?? 0 }
        } ?? 0
        let caption: String? = switch weeks {
        case 0: "This week"
        case 1: "Next week"
        case -1: "Last week"
        default: nil
        }
        return DayHeader(day: day, isToday: weeks == 0, weekTitle: WeekLayout.title(days, now: store.now, calendar: .current),
                         mode: $viewMode, onChange: step, onToday: showToday, onPick: show(day:)) {
            caption.map(Text.init)
        }
    }

    /// The day as a one-column hour grid, at the popover's usual width.
    private func dayGridContent(day: Date) -> some View {
        WeekView(
            days: [Calendar.current.startOfDay(for: day)],
            contents: [store.events(for: day)],
            now: store.now,
            startHour: min(max(weekStartHour, 0), 23),
            endHour: min(max(weekEndHour, weekStartHour + 1), 24),
            onShowDay: { _ in withAnimation(Motion.resize) { viewMode = .day } },
            onJoin: join,
            width: 380,
            composer: app.composer
        )
    }

    private func weekContent(day: Date) -> some View {
        let days = weekDays(day)
        return WeekView(
            days: days,
            contents: store.events(forWeek: days),
            now: store.now,
            startHour: min(max(weekStartHour, 0), 23),
            endHour: min(max(weekEndHour, weekStartHour + 1), 24),
            onShowDay: { picked in
                withAnimation(Motion.resize) { viewMode = .day }
                show(day: picked)
            },
            onJoin: join,
            composer: app.composer
        )
    }

    // MARK: peek

    private var peekHint: some View {
        HStack(spacing: 4) {
            Text("Click for the whole day")
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    // MARK: header

    private func header(_ agenda: DayAgenda, day: Date, other: DayContent?) -> some View {
        DayHeader(day: day, isToday: other == nil, mode: $viewMode, onChange: step, onToday: showToday, onPick: show(day:)) {
            if let other {
                DayHeader.otherDayInfo(other, offset: dayOffset)
            } else if store.isOffline, let last = store.lastFetch {
                Label("offline · updated \(AgendaFormat.duration(store.now.timeIntervalSince(last))) ago",
                      systemImage: "wifi.slash")
            } else if store.isLoading {
                Text("Today")
            } else {
                Text(agenda.current.isEmpty ? "Today · nothing left" : "Today · \(agenda.current.count) left")
            }
        }
    }

    // MARK: content

    /// Rows reachable with the arrow keys, in display order.
    static func rows(_ agenda: DayAgenda, _ other: DayContent?, showEnded: Bool) -> [CalendarEvent] {
        switch other {
        case nil: agenda.current + (showEnded ? agenda.past : [])
        case .loaded(let listing): listing.timed
        case .loading, .failed: []
        }
    }

    @ViewBuilder
    /// `peekID`: set during a peek, to the meeting shown alone (nil inside
    /// when there is none).
    private func content(
        _ agenda: DayAgenda, day: Date, other: DayContent?, rows: [CalendarEvent], focusID: String?,
        peekID: String?? = nil
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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let other {
                            otherDayList(other, day: day)
                        } else {
                            todayList(agenda, rows: rows, focusID: focusID, peekID: peekID)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 8)
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
    private func todayList(_ agenda: DayAgenda, rows: [CalendarEvent], focusID: String?,
                           peekID: String??) -> some View {
        let peeking = peekID != nil
        // All-day events stay on top, above "Nothing
        // left today" once the timed ones are over.
        if !agenda.allDay.isEmpty && !peeking {
            AllDayStrip(events: agenda.allDay)
        }
        if store.isLoading {
            LoadingRow()
        } else if agenda.current.isEmpty || peekID == .some(nil) {
            endOfDay(agenda.firstTomorrow)
        }
        let gaps = FreeTime.gaps(agenda.current)
        ForEach(Array(agenda.current.enumerated()), id: \.element.id) { index, event in
            if !peeking || event.id == peekID {
                if !peeking, let gap = gaps[event.id] {
                    FreeGap(interval: gap)
                }
                row(event, index: index, isPast: false, focusID: focusID)
            }
        }
        // Ended events come after the toggle that unfolds them.
        if !agenda.past.isEmpty && !peeking {
            endedToggle(agenda.past.count)
            if showEnded {
                ForEach(Array(agenda.past.enumerated()), id: \.element.id) { offset, event in
                    row(event, index: agenda.current.count + offset, isPast: true, focusID: focusID)
                }
            }
        }
    }

    /// `index` is the position in `rows`, for the keyboard selection.
    private func row(_ event: CalendarEvent, index: Int, isPast: Bool, focusID: String?) -> some View {
        EventRow(
            event: event,
            now: store.now,
            selected: index == selectedIndex,
            expanded: event.id == focusID || expandedID == event.id,
            isPast: isPast,
            isFocus: event.id == focusID,
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

    /// Folds and unfolds today's ended events, below the upcoming ones.
    private func endedToggle(_ count: Int) -> some View {
        Button {
            withAnimation(Motion.resize) {
                showEnded.toggle()
                // The selection may point into the rows just folded.
                if !showEnded { selectedIndex = min(selectedIndex, max(store.agenda.current.count - 1, 0)) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(showEnded ? 90 : 0))
                Text(count == 1 ? "1 ended earlier" : "\(count) ended earlier")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: footer

    /// The footer, with the "Undo" bar of a deletion above it.
    private var footer: some View {
        VStack(spacing: 0) {
            if let deleted = store.lastDeleted {
                UndoBar(title: deleted.title, onUndo: store.undoDelete)
                Divider()
            } else if let error = store.deleteError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("OK", action: store.dismissDeleteError).controlSize(.small)
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                Divider()
            }
            MenuFooter(isRefreshing: store.isRefreshing, onRefresh: {
                Task { await store.refresh() }
            }, calendarURL: GoogleCalendarWeb.home(authuser: accounts.accounts.first?.email)) {
                SettingsView()
            }
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
        withAnimation(Motion.resize) {
            expandedID = expandedID == event.id ? nil : event.id
        }
    }

    /// Backspace or forward delete, whatever character macOS sends for it.
    static func isDeleteKey(_ press: KeyPress) -> Bool {
        press.key == .delete || press.key == .deleteForward
            || press.characters == "\u{7F}" || press.characters == "\u{08}" || press.characters == "\u{F728}"
    }

    /// Previous or next day, or week in the week view.
    private func step(_ direction: Int) {
        changeDay(by: viewMode.isDay ? direction : 7 * direction)
    }

    private func changeDay(by delta: Int) {
        dayOffset += delta
        expandedID = nil
        selectedIndex = 0
    }

    /// Jumps to the day of `date`, counted in calendar days from today.
    private func show(day date: Date) {
        let calendar = Calendar.current
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: store.now),
                                            to: calendar.startOfDay(for: date)).day ?? 0
        changeDay(by: delta - dayOffset)
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
        // A requested ended event unfolds its section.
        if store.agenda.past.contains(where: { $0.id == id }) { showEnded = true }
        let rows = Self.rows(store.agenda, nil, showEnded: showEnded)
        if let index = rows.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }
}

/// Empty state until a Google OAuth client is imported: Calbar ships
/// without one, each user brings their own.
private struct OAuthClientSetup: View {
    @ObservedObject private var app = AppDelegate.shared

    static let helpURL = URL(string: "https://github.com/emilevauge/calbar#google-oauth-client")!

    var body: some View {
        VStack(spacing: 10) {
            Text("Calbar needs a Google OAuth client")
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
