import SwiftUI
import CalbarCore

/// Above the week grid while finding a time: the event, one chip per
/// person to show everyone or someone alone, the legend, and Done.
struct FindTimeBar: View {
    let session: EventStore.FindTime
    let onToggle: (String) -> Void
    let onEveryone: () -> Void
    let onDone: () -> Void

    var body: some View {
        let everyone = session.shown.count == session.people.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.secondary)
                Text("Find a time for \u{201C}\(session.event.title)\u{201D}")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(AgendaFormat.duration(session.event.end.timeIntervalSince(session.event.start)))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if session.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Done", action: onDone)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            FlowLayout(spacing: 4, lineSpacing: 4) {
                chip(selected: everyone, help: "Show everyone's availability", action: onEveryone) {
                    Image(systemName: "person.2.fill").font(.system(size: 9))
                    Text("Everyone")
                }
                ForEach(session.people, id: \.email) { person in
                    let key = person.email.lowercased()
                    let unknown = session.availability[key] == .unknown
                    chip(selected: !everyone && session.shown.contains(key),
                         help: unknown ? "\(person.email): calendar not shared" : person.email,
                         action: { onToggle(person.email) }) {
                        Avatar(person: person, response: .accepted)
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                        Text(Self.firstName(person))
                        if unknown {
                            Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
                        }
                    }
                    .opacity(everyone || session.shown.contains(key) ? 1 : 0.5)
                }
            }
            HStack(spacing: 12) {
                legend(Color.green.opacity(0.35), session.shown.count > 1 ? "Free for everyone shown" : "Free")
                legend(Color.primary.opacity(0.14), "Busy")
                Spacer(minLength: 0)
                if let error = session.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if session.canMove {
                    Text("Click a time to move the event there.")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
    let start: Date
    let end: Date
    /// Names of the people busy then.
    let busy: [String]
    /// Names of the people whose calendar is not shared.
    let unknown: [String]
    let onMove: () async throws -> Void
    let onCancel: () -> Void
    @State private var moving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move \u{201C}\(event.title)\u{201D}")
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
                Text(event.attendees.contains { !$0.isSelf } ? "Guests get the update." : "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: onCancel)
                Button {
                    moving = true
                    error = nil
                    Task {
                        do {
                            try await onMove()
                        } catch {
                            self.error = describeCreate(error).replacingOccurrences(of: "add the event", with: "move the event")
                        }
                        moving = false
                    }
                } label: {
                    if moving { ProgressView().controlSize(.small) } else { Text("Move") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(moving)
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .frame(width: 280)
        .padding(14)
    }
}
