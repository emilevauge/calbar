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

/// Window to fill in a new event, opened once a slot of the hour grid is
/// selected. One at a time: a new selection replaces it.
@MainActor
final class EventEditorWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onClose: () -> Void = {}

    func show(start: Date, end: Date, calendars: [WritableCalendar],
              create: @escaping (NewEvent, String) async throws -> Void) {
        window?.close()
        let editor = EventEditor(start: start, end: end, calendars: calendars, onCreate: create) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "New Event"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: editor)
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 440, height: 420))
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose()
    }
}

/// The details of a new event: title, day and times, calendar, location,
/// guests, Google Meet link and description. The last calendar and the
/// Meet choice are remembered.
struct EventEditor: View {
    let calendars: [WritableCalendar]
    let onCreate: (NewEvent, String) async throws -> Void
    let onDone: () -> Void

    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var location = ""
    @State private var guestText = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?
    @AppStorage("newEventCalendar") private var calendarID = ""
    @AppStorage("newEventMeet") private var addMeet = true
    @FocusState private var titleFocused: Bool

    init(start: Date, end: Date, calendars: [WritableCalendar],
         onCreate: @escaping (NewEvent, String) async throws -> Void, onDone: @escaping () -> Void) {
        self.calendars = calendars
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

    private var guests: [String] { NewEvent.guests(from: guestText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if calendars.isEmpty {
                Text("No calendar to add to. Reconnect your account in Settings to create events.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close", action: onDone).keyboardShortcut(.cancelAction)
                }
            } else {
                form
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 440)
        .onAppear { titleFocused = true }
    }

    @ViewBuilder
    private var form: some View {
        TextField("Add title", text: $title)
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .focused($titleFocused)
            .onSubmit(create)
        Divider()

        row("clock") {
            DatePicker("Day", selection: dayBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
            DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                // Moving the start keeps the duration.
                .onChange(of: start) { old, new in end = end.addingTimeInterval(new.timeIntervalSince(old)) }
            Text("-").foregroundStyle(.secondary)
            DatePicker("End", selection: $end, in: start.addingTimeInterval(5 * 60)..., displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
            Text(AgendaFormat.duration(end.timeIntervalSince(start)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }

        row("calendar") {
            Circle()
                .fill(Color(hex: selected?.calendar.colorHex ?? "#888888"))
                .frame(width: 8, height: 8)
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

        row("video") {
            Toggle("Add a Google Meet link", isOn: $addMeet)
        }

        row("person.2") {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Add guests (emails)", text: $guestText)
                    .textFieldStyle(.roundedBorder)
                if !guests.isEmpty {
                    Text(guests.count == 1 ? "1 guest, who gets an invitation" : "\(guests.count) guests, who get an invitation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        row("mappin.and.ellipse") {
            TextField("Add location", text: $location)
                .textFieldStyle(.roundedBorder)
        }

        row("text.alignleft", alignment: .top) {
            TextEditor(text: $notes)
                .font(.body)
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Add description")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 9)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
        }

        if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack {
            if busy { ProgressView().controlSize(.small) }
            Spacer()
            Button("Cancel", action: onDone)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: create)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(busy || selected == nil)
        }
    }

    /// Changing the day moves both times, keeping the hours.
    private var dayBinding: Binding<Date> {
        Binding(get: { start }, set: { day in
            let cal = Calendar.current
            let shift = cal.startOfDay(for: day).timeIntervalSince(cal.startOfDay(for: start))
            start = start.addingTimeInterval(shift)
        })
    }

    private func row<Content: View>(_ symbol: String, alignment: VerticalAlignment = .center,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, alignment == .top ? 5 : 0)
            content()
            Spacer(minLength: 0)
        }
    }

    private func create() {
        guard !busy, let target = selected else { return }
        busy = true
        error = nil
        let event = NewEvent(title: title, start: start, end: max(end, start.addingTimeInterval(5 * 60)),
                             calendarID: target.calendar.id, addMeet: addMeet,
                             location: location, notes: notes, guests: guests)
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
