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

/// Borderless panel that takes the keyboard without activating a window
/// of its own, so the main popover stays open beside it.
private final class EditorPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

/// The editor of a new event, beside the main popover. One at a time.
@MainActor
final class EventEditorWindow {
    private var panel: NSPanel?
    var onClose: () -> Void = {}

    var isShown: Bool { panel?.isVisible == true }

    /// `beside`: the main popover's window, to sit to its left (or right
    /// when there is no room).
    func show(start: Date, end: Date, calendars: [WritableCalendar], contacts: ContactBook,
              beside anchor: NSWindow?, create: @escaping (NewEvent, String) async throws -> Void) {
        close()
        let editor = EventEditor(start: start, end: end, calendars: calendars, contacts: contacts,
                                 onCreate: create) { [weak self] in self?.close() }
        let panel = EditorPanel()
        let host = NSHostingView(rootView: editor)
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        if let anchor, let screen = anchor.screen ?? NSScreen.main {
            let frame = anchor.frame
            let visible = screen.visibleFrame
            var x = frame.minX - size.width - 8
            if x < visible.minX + 8 { x = min(frame.maxX + 8, visible.maxX - size.width - 8) }
            let y = min(frame.maxY - size.height - 12, visible.maxY - size.height - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: max(y, visible.minY + 8)))
        } else {
            panel.center()
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        onClose()
    }
}

/// The details of a new event, in the look of the event cards: title,
/// day and times, calendar, Google Meet link, guests with suggestions,
/// location and description. The last calendar and the Meet choice are
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
        VStack(alignment: .leading, spacing: 10) {
            if calendars.isEmpty {
                Text("No calendar to add to. Reconnect your account in Settings to create events.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close", action: onDone).keyboardShortcut(.cancelAction)
                }
            } else {
                header(color)
                details
                footer
            }
        }
        .padding(14)
        .frame(width: 360)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(.regularMaterial)
            shape.fill(color.opacity(0.07))
            shape.strokeBorder(color.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { titleFocused = true }
    }

    // MARK: parts

    /// "NEW" and the time range, then the title, like a card's header.
    private func header(_ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("NEW EVENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
            }
            TextField("Add title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($titleFocused)
                .onSubmit(create)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("clock") {
                DatePicker("Day", selection: dayBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    // Moving the start keeps the duration.
                    .onChange(of: start) { old, new in end = end.addingTimeInterval(new.timeIntervalSince(old)) }
                Text("-")
                DatePicker("End", selection: $end, in: start.addingTimeInterval(5 * 60)..., displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                Text(AgendaFormat.duration(end.timeIntervalSince(start)))
                    .fixedSize()
            }
            line("calendar") {
                Picker("Calendar", selection: Binding(get: { selected?.id ?? "" }, set: { calendarID = $0 })) {
                    ForEach(Self.byAccount(calendars), id: \.0) { email, list in
                        Section(email) {
                            ForEach(list) { item in Text(item.calendar.name).tag(item.id) }
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            line("video") {
                Toggle("Add a Google Meet link", isOn: $addMeet)
                    .toggleStyle(.checkbox)
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
                    .lineLimit(2...6)
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

    private var footer: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel", action: onDone)
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
            Button(action: create) {
                Text("Save").font(.system(size: 12, weight: .semibold))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(busy || selected == nil)
        }
        .padding(.top, 2)
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

/// Guests as chips, then a field with suggestions under it: `↑` `↓` move,
/// `↵` or `tab` picks, `,` or `↵` adds a typed email, `⌫` in the empty
/// field removes the last chip.
private struct GuestField: View {
    @Binding var guests: [ContactIndex.Contact]
    @ObservedObject var contacts: ContactBook
    @State private var text = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var suggestions: [ContactIndex.Contact] {
        contacts.index.search(text, excluding: Set(guests.map(\.email)))
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
