import SwiftUI
import CalbarCore

/// Above the week grid while finding a time: the event, one chip per
/// person to show everyone or someone alone, the legend, and Done.
struct FindTimeBar: View {
    let title: String
    let duration: TimeInterval
    let people: [Person]
    /// Lowercased emails shown.
    let shown: Set<String>
    let availability: [String: FreeBusy.Availability]
    /// Group emails to their members, lowercased.
    let groups: [String: [String]]
    let isLoading: Bool
    let error: String?
    /// Under the legend, on the right.
    let hint: String?
    let onToggle: (String) -> Void
    let onEveryone: () -> Void
    /// Done, when the bar ends a mode of its own.
    var onDone: (() -> Void)?
    /// Groups opened on their members.
    @State private var expanded: Set<String> = []

    init(session: EventStore.FindTime, onToggle: @escaping (String) -> Void, onEveryone: @escaping () -> Void,
         onDone: @escaping () -> Void) {
        title = "Reschedule \u{201C}\(session.event.title)\u{201D}"
        duration = session.event.end.timeIntervalSince(session.event.start)
        people = session.people
        shown = session.shown
        availability = session.availability
        groups = session.result.groups
        isLoading = session.isLoading
        error = session.error
        hint = session.canMove ? "Click a time to move the event there."
            : session.proposes ? "Click a time to propose it to the organizer." : nil
        self.onToggle = onToggle
        self.onEveryone = onEveryone
        self.onDone = onDone
    }

    init(composing session: EventStore.Composing, onToggle: @escaping (String) -> Void,
         onEveryone: @escaping () -> Void) {
        title = "Guests' availability"
        duration = session.end.timeIntervalSince(session.start)
        people = session.people.map { Person(email: $0, name: session.fullNames[$0]) }
        shown = session.shownEmails
        availability = session.availability
        groups = session.result.groups
        isLoading = session.isLoading
        error = nil
        hint = "Click or drag on the grid to set the time."
        self.onToggle = onToggle
        self.onEveryone = onEveryone
        onDone = nil
    }

    var body: some View {
        let everyone = shown.count == people.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(AgendaFormat.duration(duration))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                if let onDone {
                    Button("Done", action: onDone)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                }
            }
            FlowLayout(spacing: 4, lineSpacing: 4) {
                chip(selected: everyone, help: "Show everyone's availability", action: onEveryone) {
                    Image(systemName: "person.2.fill").font(.system(size: 9))
                    Text("Everyone")
                }
                ForEach(people, id: \.email) { person in
                    let key = person.email.lowercased()
                    if let members = groups[key] {
                        groupChip(person, members: members, everyone: everyone)
                        if expanded.contains(key) {
                            ForEach(members, id: \.self) { member in
                                personChip(Person(email: member, name: nil), everyone: everyone, inGroup: key)
                            }
                        }
                    } else {
                        personChip(person, everyone: everyone, inGroup: nil)
                    }
                }
            }
            HStack(spacing: 12) {
                legend(Color.green.opacity(0.35), shown.count > 1 ? "Free for everyone shown" : "Free")
                legend(Color.primary.opacity(0.14), "Busy")
                Spacer(minLength: 0)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let hint {
                    Text(hint)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// A person, or a group's member (smaller, tinted like its group).
    private func personChip(_ person: Person, everyone: Bool, inGroup group: String?) -> some View {
        let key = person.email.lowercased()
        let unknown = availability[key] == .unknown
        let isShown = shown.contains(key) || group.map { shown.contains($0) } == true
        return chip(selected: !everyone && isShown,
                    help: unknown ? "\(person.email): calendar not shared" : person.email,
                    action: { onToggle(person.email) }) {
            Avatar(person: person, response: .accepted)
                .scaleEffect(group == nil ? 0.8 : 0.65)
                .frame(width: group == nil ? 16 : 13, height: group == nil ? 16 : 13)
            Text(Self.firstName(person))
                .font(.system(size: group == nil ? 12 : 11))
            if unknown {
                Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
            }
        }
        .opacity(everyone || isShown ? 1 : 0.5)
    }

    /// A group: its name and size, a chevron to show its members.
    private func groupChip(_ person: Person, members: [String], everyone: Bool) -> some View {
        let key = person.email.lowercased()
        let isShown = shown.contains(key)
        let open = expanded.contains(key)
        return HStack(spacing: 0) {
            chip(selected: !everyone && isShown, help: "\(person.email): \(members.count) people",
                 action: { onToggle(person.email) }) {
                Image(systemName: "person.3.fill").font(.system(size: 9))
                Text("\(Self.firstName(person)) (\(members.count))")
                Button {
                    withAnimation(Motion.resize) {
                        if open { expanded.remove(key) } else { expanded.insert(key) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 12, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? "Hide the members" : "Show the members")
            }
        }
        .opacity(everyone || isShown || members.contains(where: shown.contains) ? 1 : 0.5)
    }

    static func firstName(_ person: Person) -> String {
        if let name = person.name, let first = name.split(separator: " ").first { return String(first) }
        return String(person.email.split(separator: "@").first ?? Substring(person.email))
    }

    private func chip<Label: View>(selected: Bool, help: String, action: @escaping () -> Void,
                                   @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 4) { label() }
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// The confirmation on a picked time: the new times, who is busy then,
/// and Move.
struct MoveConfirm: View {
    let event: CalendarEvent
    /// Not the user's event: the time goes to the organizer as a proposal.
    var proposes = false
    let start: Date
    let end: Date
    /// Names of the people busy then.
    let busy: [String]
    /// Names of the people whose calendar is not shared.
    let unknown: [String]
    /// The occurrences to move: always this one for a single event.
    let onMove: (RecurrenceScope) async throws -> Void
    let onCancel: () -> Void
    @State private var moving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(proposes ? "Propose a new time for \u{201C}\(event.title)\u{201D}" : "Move \u{201C}\(event.title)\u{201D}")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(DayHeaderText.shortTitle(start))
                Text("\(AgendaFormat.clock(start, .current)) \u{2192} \(AgendaFormat.clock(end, .current))")
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            if busy.isEmpty {
                Label(unknown.isEmpty ? "Everyone is free" : "Everyone else is free", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Busy: \(busy.joined(separator: ", "))", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !unknown.isEmpty {
                Label("Not shared: \(unknown.joined(separator: ", "))", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(proposes ? "Sent to the organizer with your answer."
                     : event.attendees.contains { !$0.isSelf } ? "Guests get the update." : "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: onCancel)
                if event.isRecurring && !proposes {
                    if moving {
                        ProgressView().controlSize(.small)
                    } else {
                        Menu("Move") {
                            ForEach(RecurrenceScope.allCases, id: \.self) { scope in
                                Button(scope.label) { run(scope) }
                            }
                        }
                        .fixedSize()
                    }
                } else {
                    Button {
                        run(.this)
                    } label: {
                        if moving { ProgressView().controlSize(.small) } else { Text(proposes ? "Propose" : "Move") }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(moving)
                }
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .frame(width: 280)
        .padding(14)
    }

    private func run(_ scope: RecurrenceScope) {
        moving = true
        error = nil
        Task {
            do {
                try await onMove(scope)
            } catch {
                self.error = describeCreate(error).replacingOccurrences(
                    of: "add the event", with: proposes ? "send the proposal" : "move the event")
            }
            moving = false
        }
    }
}
