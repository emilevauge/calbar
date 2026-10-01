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

/// What the hour grid needs to create events: where they may go, guest
/// suggestions, and the call that creates one.
struct EventComposer {
    let calendars: [WritableCalendar]
    let contacts: ContactBook
    let create: (NewEvent, String) async throws -> Void
}

/// The details of a new event, in a popover on the selected slot, laid
/// out as the event cards: the times where a card has its time range, the
/// title, Save where a card has Join, then the lines: calendar, Google
/// Meet link, guests with suggestions, location and description. The last calendar and the Meet choice are
/// remembered.
struct EventEditor: View {
    let calendars: [WritableCalendar]
    @ObservedObject var contacts: ContactBook
    let onCreate: (NewEvent, String) async throws -> Void
    let onDone: () -> Void

    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var location = ""
    @State private var guests: [ContactIndex.Contact] = []
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?
    @AppStorage("newEventCalendar") private var calendarID = ""
    @AppStorage("newEventMeet") private var addMeet = true
    @FocusState private var titleFocused: Bool

    init(start: Date, end: Date, calendars: [WritableCalendar], contacts: ContactBook,
         onCreate: @escaping (NewEvent, String) async throws -> Void, onDone: @escaping () -> Void) {
        self.calendars = calendars
        self.contacts = contacts
        self.onCreate = onCreate
        self.onDone = onDone
        _start = State(initialValue: start)
        _end = State(initialValue: end)
    }

    /// The remembered calendar, else the first primary one.
    private var selected: WritableCalendar? {
        calendars.first { $0.id == calendarID }
            ?? calendars.first { $0.calendar.isPrimary }
            ?? calendars.first
    }

    var body: some View {
        let color = Color(hex: selected?.calendar.colorHex ?? "#4285f4")
        Group {
            if calendars.isEmpty {
                Text("No calendar to add to. Reconnect your account in Settings to create events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                card(color)
            }
        }
        .frame(width: 360)
        .padding(.vertical, 6)
        .onAppear { titleFocused = true }
    }

    // MARK: parts

    /// The same box as `EventRow`'s card.
    private func card(_ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    times
                    TextField("Add title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .focused($titleFocused)
                        .onSubmit(create)
                }
                Spacer(minLength: 0)
                Button(action: create) {
                    Group {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || selected == nil)
            }
            details
        }
        .padding(12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape.fill(color.opacity(0.07))
            shape.strokeBorder(color.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    /// Day, start and end, and the duration, in the caption of a card.
    /// The day opens the same month calendar as the header; each time
    /// opens a list of quarter hours, as in Google Calendar.
    private var times: some View {
        HStack(spacing: 2) {
            PopoverField(label: DayHeaderText.shortTitle(start), help: "Pick the day") { close in
                DayPicker(day: start, isToday: Calendar.current.isDateInToday(start), onPick: { day in
                    dayBinding.wrappedValue = day
                    close()
                }, onToday: {
                    dayBinding.wrappedValue = Date()
                    close()
                })
            }
            PopoverField(label: AgendaFormat.clock(start, .current), help: "Start time") { close in
                TimeList(options: TimeList.day(of: start), selection: start, reference: nil) { picked in
                    let duration = end.timeIntervalSince(start)
                    start = picked
                    end = picked.addingTimeInterval(duration)
                    close()
                }
            }
            Text("-")
            PopoverField(label: AgendaFormat.clock(end, .current), help: "End time") { close in
                TimeList(options: TimeList.after(start), selection: end, reference: start) { picked in
                    end = picked
                    close()
                }
            }
            Text("· \(AgendaFormat.duration(end.timeIntervalSince(start)))")
                .fixedSize()
                .padding(.leading, 2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("calendar") {
                Circle()
                    .fill(Color(hex: selected?.calendar.colorHex ?? "#888888"))
                    .frame(width: 7, height: 7)
                Picker("Calendar", selection: Binding(get: { selected?.id ?? "" }, set: { calendarID = $0 })) {
                    ForEach(Self.byAccount(calendars), id: \.0) { email, list in
                        Section(email) {
                            ForEach(list) { item in Text(item.calendar.name).tag(item.id) }
                        }
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            line("video") {
                Toggle("Google Meet", isOn: $addMeet)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }
            line("person.2", alignment: .top) {
                GuestField(guests: $guests, contacts: contacts)
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
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// An icon and its content, as in the event details.
    private func line<Content: View>(_ symbol: String, alignment: VerticalAlignment = .center,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: alignment == .top ? .firstTextBaseline : .center, spacing: 6) {
            Image(systemName: symbol)
                .frame(width: 14)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Changing the day moves both times, keeping the hours.
    private var dayBinding: Binding<Date> {
        Binding(get: { start }, set: { day in
            let cal = Calendar.current
            start = start.addingTimeInterval(cal.startOfDay(for: day).timeIntervalSince(cal.startOfDay(for: start)))
        })
    }

    private func create() {
        guard !busy, let target = selected else { return }
        busy = true
        error = nil
        let event = NewEvent(title: title, start: start, end: max(end, start.addingTimeInterval(5 * 60)),
                             calendarID: target.calendar.id, addMeet: addMeet,
                             location: location, notes: notes, guests: guests.map(\.email))
        Task {
            do {
                try await onCreate(event, target.email)
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
            if focused, contacts.needsReconnectForGoogle, text.count >= 2 {
                Text("Reconnect your account in Settings to search your Google contacts.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if focused, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.email) { i, contact in
                        Button { add(contact) } label: {
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(Color.primary.opacity(open || hovering ? 0.1 : 0.05),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
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
