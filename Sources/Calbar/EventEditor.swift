import SwiftUI
import AppKit
import CalbarCore

/// A calendar a new event can go to, with its account.
struct WritableCalendar: Identifiable, Hashable {
    let email: String
    let calendar: CalendarInfo
    var id: String { "\(email)|\(calendar.id)" }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What the editor needs: where events may go, guest suggestions, and
/// the calls that create and update one.
struct EventComposer {
    let calendars: [WritableCalendar]
    let contacts: ContactBook
    let zoom: ZoomAuth
    let create: (NewEvent, String) async throws -> Void
    /// The event, the edited copy, the description as shown, which occurrences.
    let update: (CalendarEvent, NewEvent, String, RecurrenceScope) async throws -> Void
}

/// The details of an event, in a popover, laid out as the event cards:
/// the times where a card has its time range, the title, Save where a
/// card has Join, then the lines: calendar, video call, repetition,
/// guests with suggestions, location and description. Creates an event,
/// changes one (`.edit`), or creates a copy of one (`.duplicate`). The
/// last calendar and video call choice are remembered for new events.
struct EventEditor: View {
    enum Mode {
        case create
        case edit(CalendarEvent)
        case duplicate(CalendarEvent)
    }

    let mode: Mode
    let composer: EventComposer
    @ObservedObject var contacts: ContactBook
    @ObservedObject var zoom: ZoomAuth
    let onDone: () -> Void

    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay = false
    @State private var location = ""
    @State private var guests: [ContactIndex.Contact] = []
    @State private var notes = ""
    /// The description as the event had it, in plain text: unchanged, its
    /// HTML is kept.
    private let notesText: String
    @State private var repeatRule: RepeatRule = .none
    @State private var scope: RecurrenceScope = .this
    @State private var busy = false
    @State private var error: String?
    @AppStorage("newEventCalendar") private var calendarID = ""
    /// "none", "meet" or "zoom", remembered.
    @AppStorage("newEventConference") private var conference = "meet"
    /// The choices of this editor when they differ from the remembered ones.
    @State private var chosenCalendar: String?
    @State private var chosenConference: String?
    @FocusState private var titleFocused: Bool
    @ObservedObject private var store = AppDelegate.shared.store
    static let width: CGFloat = 360
    /// `esc` with changes: asks before throwing them away.
    @State private var confirmingDiscard = false
    /// The fields as the editor opened, to tell whether anything changed.
    @State private var initialFields = ""

    /// The editor of `session`, beside the week grid.
    init(session: EventStore.Composing, composer: EventComposer, onDone: @escaping () -> Void) {
        switch session.mode {
        case .create:
            self.init(mode: .create, start: session.start, end: session.end, composer: composer, onDone: onDone)
        case .edit(let event):
            self.init(mode: .edit(event), start: session.start, end: session.end, composer: composer,
                      onDone: onDone, from: event)
        case .duplicate(let event):
            self.init(mode: .duplicate(event), start: session.start, end: session.end, composer: composer,
                      onDone: onDone, from: event)
        }
    }

    private init(mode: Mode, start: Date, end: Date, composer: EventComposer, onDone: @escaping () -> Void,
                 from event: CalendarEvent? = nil) {
        self.mode = mode
        self.composer = composer
        self.contacts = composer.contacts
        self.zoom = composer.zoom
        self.onDone = onDone
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        let text = event.map { HTMLText.plainText($0.notes ?? "") } ?? ""
        notesText = text
        guard let event else { return }
        _title = State(initialValue: event.title == "(No title)" ? "" : event.title)
        _isAllDay = State(initialValue: event.isAllDay)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: text)
        _guests = State(initialValue: event.attendees.filter { !$0.isSelf }
            .map { ContactIndex.Contact(email: $0.person.email, name: $0.person.name) })
        let own = composer.calendars.first { $0.email == event.accountEmail && $0.calendar.id == event.calendarID }
        _chosenCalendar = State(initialValue: own?.id)
        if case .duplicate = mode {
            // A new Meet link for a copy of a Meet; other links stay in the
            // copied location or description.
            _chosenConference = State(initialValue: event.meeting?.provider == .meet ? "meet" : "none")
        } else {
            _chosenConference = State(initialValue: "none")
        }
    }

    private var original: CalendarEvent? {
        if case .edit(let event) = mode { return event }
        return nil
    }

    /// This editor's calendar, else the remembered one, else the first
    /// primary one.
    private var selected: WritableCalendar? {
        let calendars = composer.calendars
        return calendars.first { $0.id == chosenCalendar }
            ?? calendars.first { $0.id == calendarID }
            ?? calendars.first { $0.calendar.isPrimary }
            ?? calendars.first
    }

    var body: some View {
        let color = Color(hex: original?.colorHex ?? selected?.calendar.colorHex ?? "#4285f4")
        Group {
            if composer.calendars.isEmpty {
                Text("No calendar to add to. Reconnect your account in Settings to create events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            } else {
                form(color)
                    .padding(16)
            }
        }
        .frame(width: Self.width)
        .onAppear {
            contacts.prepare()
            initialFields = fields
            titleFocused = true
            report()
        }
        // The grid draws the times and the guests' availability, and
        // changes the times on a click.
        .onChange(of: reportKey) { report() }
        .onChange(of: store.composing?.start) { _, new in
            if let new, new != start { start = new }
        }
        .onChange(of: store.composing?.end) { _, new in
            if let new, new != end { end = new }
        }
        // `esc` closes only after asking when something was typed: the
        // popover would otherwise go, and the event with it.
        .onEscape(cancel)
    }

    // MARK: parts

    /// The title beside the calendar's color, the times, the fields with
    /// an icon each, then Cancel and Save.
    private func form(_ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 4, height: 20)
                TextField(original == nil ? "New event" : "Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit(save)
            }
            times
                .padding(.top, 10)
                .padding(.leading, 13)
            Divider()
                .padding(.vertical, 12)
            details
            if error != nil || confirmingDiscard {
                Divider().padding(.vertical, 10)
                notice
            }
            Divider()
                .padding(.vertical, 12)
            footer
        }
    }

    /// Day, start and end as pills that open their picker, then the
    /// duration. The day opens the same month calendar as the header;
    /// each time a list of quarter hours, as in Google Calendar. An
    /// all-day event has its day alone.
    private var times: some View {
        HStack(spacing: 6) {
            PopoverField(label: DayHeaderText.shortTitle(start), help: "Pick the day") { close in
                DayPicker(day: start, isToday: Calendar.current.isDateInToday(start), onPick: { day in
                    moveDay(to: day)
                    close()
                }, onToday: {
                    moveDay(to: Date())
                    close()
                })
            }
            if isAllDay {
                let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
                Text(days > 1 ? "All day, \(days) days" : "All day")
                    .foregroundStyle(.secondary)
            } else {
                PopoverField(label: AgendaFormat.clock(start, .current), help: "Start time") { close in
                    TimeList(options: TimeList.day(of: start), selection: start, reference: nil) { picked in
                        let duration = end.timeIntervalSince(start)
                        start = picked
                        end = picked.addingTimeInterval(duration)
                        close()
                    }
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                PopoverField(label: AgendaFormat.clock(end, .current), help: "End time") { close in
                    TimeList(options: TimeList.after(start), selection: end, reference: start) { picked in
                        end = picked
                        close()
                    }
                }
                Text(AgendaFormat.duration(end.timeIntervalSince(start)))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            line(color: Color(hex: selected?.calendar.colorHex ?? "#888888")) {
                if let original {
                    // Moving an event to another calendar is not supported.
                    Text(selected?.calendar.name ?? original.calendarID)
                } else {
                    MenuField(label: selected?.calendar.name ?? "Calendar") {
                        ForEach(Self.byAccount(composer.calendars), id: \.0) { email, list in
                            Section(email) {
                                ForEach(list) { item in
                                    CheckItem(item.calendar.name, checked: item.id == selected?.id) {
                                        chosenCalendar = item.id
                                        calendarID = item.id
                                    }
                                }
                            }
                        }
                    }
                }
            }
            line("video") {
                if let meeting = original?.meeting {
                    Text(meeting.provider.displayName)
                } else {
                    MenuField(label: Self.conferenceName(effectiveConference)) {
                        ForEach(["none", "meet"] + (zoom.isConnected ? ["zoom"] : []), id: \.self) { choice in
                            CheckItem(Self.conferenceName(choice), checked: choice == effectiveConference) {
                                chosenConference = choice
                                if original == nil { conference = choice }
                            }
                        }
                    }
                }
            }
            line("repeat") {
                if let original, original.isRecurring {
                    MenuField(label: scope == .all ? "Change all events" : "Change this event only") {
                        CheckItem("Change this event only", checked: scope == .this) { scope = .this }
                        CheckItem("Change all events", checked: scope == .all) { scope = .all }
                    }
                } else {
                    MenuField(label: repeatRule.label(start: start)) {
                        ForEach(RepeatRule.allCases, id: \.self) { rule in
                            CheckItem(rule.label(start: start), checked: rule == repeatRule) { repeatRule = rule }
                            if rule == .none { Divider() }
                        }
                    }
                }
            }
            line("person.2", alignment: .top) {
                GuestField(guests: $guests, contacts: contacts)
            }
            if !guests.isEmpty && !isAllDay {
                availabilityHint
                    .padding(.leading, 26)
            }
            line("mappin.and.ellipse") {
                TextField("Add location", text: $location)
                    .textFieldStyle(.plain)
            }
            line("text.alignleft", alignment: .top) {
                TextField("Add description", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
            }
        }
        .font(.system(size: 12))
    }

    /// What the grid shows of the guests: free slots, or who is busy at
    /// the event's time.
    private var availabilityHint: some View {
        let session = store.composing
        let conflicts = session.map { s in
            FreeBusy.conflicts(DateInterval(start: start, end: max(end, start)), busy: s.busy).map { s.names[$0] ?? FindTimeBar.firstName(Person(email: $0, name: nil)) }
        } ?? []
        return HStack(spacing: 5) {
            if session?.isLoading == true {
                ProgressView().controlSize(.mini)
                Text("Reading availability…")
            } else if session?.loadedKey == nil {
                EmptyView()
            } else if conflicts.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Everyone is free. Green slots on the grid fit everyone.")
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Busy: \(conflicts.joined(separator: ", ")). Pick a green slot on the grid.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// An error of the last save, or the question before discarding.
    @ViewBuilder
    private var notice: some View {
        if confirmingDiscard {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text(original == nil ? "Discard this event?" : "Discard your changes?")
                Spacer(minLength: 0)
                Button("Keep Editing") { withAnimation(Motion.resize) { confirmingDiscard = false } }
                Button("Discard", role: .destructive, action: onDone)
            }
            .font(.system(size: 12))
            .controlSize(.small)
        } else if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(original == nil ? "esc to cancel" : "Editing")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button("Cancel", action: cancel)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            Button(action: save) {
                Group {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(original == nil ? "Save" : "Save Changes")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(busy || selected == nil)
        }
    }

    static func conferenceName(_ choice: String) -> String {
        switch choice {
        case "meet": return "Google Meet"
        case "zoom": return "Zoom"
        default: return "No video call"
        }
    }

    /// An icon and its content, as in the event details.
    private func line<Content: View>(_ symbol: String? = nil, color: Color? = nil,
                                     alignment: VerticalAlignment = .center,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: alignment == .top ? .firstTextBaseline : .center, spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    // The calendar's line: its color.
                    Circle().fill(color ?? .gray).frame(width: 9, height: 9)
                }
            }
            .frame(width: 16)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
    }

    /// What the grid needs from the editor, as one string to watch.
    private var reportKey: String {
        "\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(selected?.email ?? "")|"
            + guests.map(\.email).joined(separator: ",")
    }

    private func report() {
        store.composingChanged(start: start, end: end, account: original?.accountEmail ?? selected?.email,
                               guests: guests.map { ($0.email, $0.name) })
    }

    /// Every field the user can change, as one string.
    private var fields: String {
        [title, "\(start.timeIntervalSince1970)", "\(end.timeIntervalSince1970)", location, notes,
         guests.map(\.email).joined(separator: ","), repeatRule.rawValue, chosenConference ?? "", chosenCalendar ?? "",
         scope.rawValue].joined(separator: "\u{1F}")
    }

    /// `esc`: closes when nothing changed or on a second `esc`, otherwise
    /// asks first.
    private func cancel() {
        guard !busy else { return }
        if fields == initialFields || confirmingDiscard {
            onDone()
        } else {
            withAnimation(Motion.resize) { confirmingDiscard = true }
        }
    }

    /// Changing the day moves both ends, keeping the hours and the length.
    private func moveDay(to day: Date) {
        let cal = Calendar.current
        let shift = cal.startOfDay(for: day).timeIntervalSince(cal.startOfDay(for: start))
        start = start.addingTimeInterval(shift)
        end = end.addingTimeInterval(shift)
    }

    /// This editor's choice, else the remembered one; Google Meet when
    /// Zoom is no longer connected.
    private var effectiveConference: String {
        let choice = chosenConference ?? conference
        return choice == "zoom" && !zoom.isConnected ? "meet" : choice
    }

    private func save() {
        guard !busy, let target = selected else { return }
        busy = true
        error = nil
        let choice = original?.meeting == nil ? effectiveConference : "none"
        let minimum: TimeInterval = isAllDay ? 86_400 : 5 * 60
        var event = NewEvent(title: title, start: start, end: max(end, start.addingTimeInterval(minimum)),
                             calendarID: original?.calendarID ?? target.calendar.id, addMeet: choice == "meet",
                             location: location, notes: notes, guests: guests.map(\.email))
        event.isAllDay = isAllDay
        if let rule = repeatRule.rrule(start: start) { event.recurrence = [rule] }
        let original = original
        let notesText = notesText
        let scope = scope
        Task {
            // The Zoom meeting first: its link goes into the event.
            if choice == "zoom" {
                do {
                    event.zoom = try await zoom.createMeeting(topic: event.summary, start: event.start,
                                                              end: event.end, agenda: notes)
                } catch {
                    busy = false
                    self.error = describeZoom(error)
                    return
                }
            }
            do {
                if let original {
                    try await composer.update(original, event, notesText, scope)
                } else {
                    try await composer.create(event, target.email)
                }
                busy = false
                onDone()
            } catch {
                busy = false
                self.error = describeCreate(error)
            }
        }
    }

    /// Accounts in their order, each with its calendars, primary first.
    static func byAccount(_ calendars: [WritableCalendar]) -> [(String, [WritableCalendar])] {
        var order: [String] = []
        var groups: [String: [WritableCalendar]] = [:]
        for item in calendars {
            if groups[item.email] == nil { order.append(item.email) }
            groups[item.email, default: []].append(item)
        }
        return order.map { email in
            (email, groups[email, default: []].sorted {
                ($0.calendar.isPrimary ? 0 : 1, $0.calendar.name) < ($1.calendar.isPrimary ? 0 : 1, $1.calendar.name)
            })
        }
    }
}

/// Guests as chips, then a field with suggestions under it, from the
/// people met and Google (contacts, other contacts, directory): `↑` `↓` move,
/// `↵` or `tab` picks, `,` or `↵` adds a typed email, `⌫` in the empty
/// field removes the last chip.
private struct GuestField: View {
    @Binding var guests: [ContactIndex.Contact]
    @ObservedObject var contacts: ContactBook
    @State private var text = ""
    @State private var highlighted = 0
    /// Google matches for `remoteQuery`.
    @State private var remote: [ContactIndex.Contact] = []
    @State private var remoteQuery = ""
    @FocusState private var focused: Bool
    /// The pointer is on the suggestions: a click there takes the focus
    /// from the field on mouse down, which must not hide them before the
    /// click lands.
    @State private var overSuggestions = false

    /// People met first, then Google matches, one per email, six at most.
    private var suggestions: [ContactIndex.Contact] {
        let taken = Set(guests.map { $0.email.lowercased() })
        var seen = taken
        let local = contacts.index.search(text, excluding: taken)
        let fromGoogle = remoteQuery == text ? remote : []
        return Array((local + fromGoogle).filter { seen.insert($0.email.lowercased()).inserted }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !guests.isEmpty {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(guests, id: \.email) { guest in chip(guest) }
                }
            }
            TextField(guests.isEmpty ? "Add guests" : "Add more", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onChange(of: text) { _, new in
                    highlighted = 0
                    if new.hasSuffix(",") || new.hasSuffix(";") { commitTyped() }
                }
                // Google, once the typing pauses.
                .task(id: text) {
                    let query = text.trimmingCharacters(in: .whitespaces)
                    guard query.count >= 2 else { remote = []; return }
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    let found = await contacts.searchGoogle(query)
                    guard !Task.isCancelled else { return }
                    remote = found
                    remoteQuery = text
                }
                .onSubmit(pick)
                .onKeyPress(.downArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlighted = min(highlighted + 1, suggestions.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard !suggestions.isEmpty else { return .ignored }
                    pick()
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard text.isEmpty, !guests.isEmpty else { return .ignored }
                    guests.removeLast()
                    return .handled
                }
            // Same condition as the list: a line that left on focus loss
            // would move the list under the pointer mid-click.
            if focused || overSuggestions, contacts.needsReconnectForGoogle, text.count >= 2 {
                Text("Reconnect your account in Settings to search your Google contacts.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if focused || overSuggestions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.email) { i, contact in
                        HStack(spacing: 6) {
                            Avatar(person: Person(email: contact.email, name: contact.name), response: .accepted)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(contact.name ?? contact.email)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if contact.name != nil {
                                    Text(contact.email).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(i == highlighted ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                        // On release wherever the pointer is: a button
                        // drops a click released outside it.
                        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in add(contact) })
                        .onHover { if $0 { highlighted = i } }
                    }
                }
                .padding(3)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { overSuggestions = $0 }
            }
        }
    }

    private func chip(_ guest: ContactIndex.Contact) -> some View {
        HStack(spacing: 3) {
            Text(guest.name ?? guest.email)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button {
                guests.removeAll { $0.email == guest.email }
            } label: {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .help(guest.email)
    }

    /// The highlighted suggestion, else the typed text as an email.
    private func pick() {
        let list = suggestions
        if list.indices.contains(highlighted) {
            add(list[highlighted])
        } else {
            commitTyped()
        }
    }

    private func commitTyped() {
        for email in NewEvent.guests(from: text) where !guests.contains(where: { $0.email.lowercased() == email.lowercased() }) {
            guests.append(.init(email: email, name: nil))
        }
        text = ""
    }

    private func add(_ contact: ContactIndex.Contact) {
        if !guests.contains(where: { $0.email.lowercased() == contact.email.lowercased() }) {
            guests.append(contact)
        }
        text = ""
        highlighted = 0
        overSuggestions = false
        focused = true
    }
}

/// A value without a bezel that opens a menu of choices, with the
/// up and down chevrons of a pop-up button.
private struct MenuField<Items: View>: View {
    let label: String
    @ViewBuilder let items: () -> Items
    @State private var hovering = false

    var body: some View {
        // A borderless menu draws an image of its label first: the
        // chevrons go after it, outside.
        HStack(spacing: 4) {
            Menu(content: items) { Text(label) }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                // The menu's own inset: aligned with the text fields.
                .padding(.leading, -3.5)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.horizontal, -6)
        .onHover { hovering = $0 }
    }
}

/// A menu item with a check mark on the current choice.
private struct CheckItem: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    init(_ title: String, checked: Bool, action: @escaping () -> Void) {
        self.title = title
        self.checked = checked
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// A caption-sized value that opens its picker in a popover: the day or a
/// time of the event editor.
private struct PopoverField<Content: View>: View {
    let label: String
    let help: String
    @ViewBuilder let content: (_ close: @escaping () -> Void) -> Content
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.primary.opacity(open || hovering ? 0.12 : 0.07),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            content { open = false }
        }
    }
}

/// Quarter hours in a scrolling list, opened on the current choice. With
/// a `reference` (the start), each end time shows the duration it gives.
struct TimeList: View {
    let options: [Date]
    let selection: Date
    let reference: Date?
    let onPick: (Date) -> Void

    /// Every quarter hour of `date`'s day.
    static func day(of date: Date) -> [Date] {
        let start = Calendar.current.startOfDay(for: date)
        return (0..<96).map { start.addingTimeInterval(TimeInterval($0 * 900)) }
    }

    /// From a quarter hour after `start` to 24 hours later.
    static func after(_ start: Date) -> [Date] {
        (1...96).map { start.addingTimeInterval(TimeInterval($0 * 900)) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        row(option).id(option)
                    }
                }
                .padding(4)
            }
            .frame(width: reference == nil ? 90 : 160, height: 220)
            .onAppear {
                let target = options.min { abs($0.timeIntervalSince(selection)) < abs($1.timeIntervalSince(selection)) }
                if let target { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private func row(_ option: Date) -> some View {
        let selected = abs(option.timeIntervalSince(selection)) < 60
        return Button { onPick(option) } label: {
            HStack(spacing: 6) {
                Text(AgendaFormat.clock(option, .current))
                    .fontWeight(selected ? .semibold : .regular)
                if let reference {
                    Text(AgendaFormat.duration(option.timeIntervalSince(reference)))
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
