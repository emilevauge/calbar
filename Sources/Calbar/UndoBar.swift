import SwiftUI
import CalbarCore

/// "Deleted “Design sync”" with Undo, and the seconds left before the
/// deletion reaches Google.
struct UndoBar: View {
    let deletion: EventStore.Deletion
    let onUndo: () -> Void
    @State private var started = Date()

    private var text: String {
        let title = "\u{201C}\(deletion.event.title)\u{201D}"
        guard deletion.event.isRecurring else { return "Deleted \(title)" }
        switch deletion.scope {
        case .this: return "Deleted this \(title)"
        case .following: return "Deleted \(title) from this one on"
        case .all: return "Deleted every \(title)"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            let left = max(0, 10 - Int(context.date.timeIntervalSince(started)))
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("\(left) s")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Button("Undo") { withAnimation(Motion.resize) { onUndo() } }
                    .controlSize(.small)
                    .keyboardShortcut("z", modifiers: .command)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .id(deletion.key)
    }
}

/// ⌫ on a recurring event: which occurrences to delete, as Google
/// Calendar asks.
struct DeleteScopeBar: View {
    let title: String
    let onPick: (RecurrenceScope) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "repeat")
                    .foregroundStyle(.secondary)
                Text("Delete the recurring \u{201C}\(title)\u{201D}?")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                Button("This event") { onPick(.this) }
                    .keyboardShortcut(.defaultAction)
                Button("This and following") { onPick(.following) }
                Button("All events") { onPick(.all) }
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
