import SwiftUI
import CalbarCore

/// A calendar a new event can go to, with its account.
struct WritableCalendar: Identifiable, Hashable {
    let email: String
    let calendar: CalendarInfo
    var id: String { "\(email)|\(calendar.id)" }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Form shown over the hour grid once a slot is clicked or dragged out:
/// title, start and end times, calendar, Google Meet link. The last calendar and the
/// Meet choice are remembered.
struct NewEventForm: View {
    let calendars: [WritableCalendar]
    let onCreate: (NewEvent, String) async throws -> Void
    let onDone: () -> Void

    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if calendars.isEmpty {
                Text("No calendar to add to. Reconnect your account in Settings to create events.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close", action: onDone)
                        .keyboardShortcut(.cancelAction)
                }
            } else {
                form
            }
        }
        .padding(12)
        .frame(width: 290)
        .onAppear { titleFocused = true }
    }

    @ViewBuilder
    private var form: some View {
        TextField("New event", text: $title)
            .textFieldStyle(.roundedBorder)
            .font(.body.weight(.medium))
            .focused($titleFocused)
            .onSubmit(create)

        HStack(spacing: 8) {
            // The day is the clicked column's; only the time is edited.
            Text(DayHeaderText.shortTitle(start))
                .foregroundStyle(.secondary)
            DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                // Moving the start keeps the duration.
                .onChange(of: start) { old, new in end = end.addingTimeInterval(new.timeIntervalSince(old)) }
            Text("-")
                .foregroundStyle(.secondary)
            DatePicker("End", selection: $end, in: start.addingTimeInterval(5 * 60)..., displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
            Text(AgendaFormat.duration(end.timeIntervalSince(start)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }

        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: selected?.calendar.colorHex ?? "#888888"))
                .frame(width: 8, height: 8)
            Picker("Calendar", selection: Binding(
                get: { selected?.id ?? "" },
                set: { calendarID = $0 }
            )) {
                ForEach(Self.byAccount(calendars), id: \.0) { email, list in
                    Section(email) {
                        ForEach(list) { item in
                            Text(item.calendar.name).tag(item.id)
                        }
                    }
                }
            }
            .labelsHidden()
        }

        Toggle("Add a Google Meet link", isOn: $addMeet)

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
            Button("Create", action: create)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || selected == nil)
        }
    }

    private func create() {
        guard !busy, let target = selected else { return }
        busy = true
        error = nil
        let event = NewEvent(title: title, start: start, end: max(end, start.addingTimeInterval(5 * 60)),
                             calendarID: target.calendar.id, addMeet: addMeet)
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
            (email, groups[email, default: []].sorted { ($0.calendar.isPrimary ? 0 : 1, $0.calendar.name) < ($1.calendar.isPrimary ? 0 : 1, $1.calendar.name) })
        }
    }
}
