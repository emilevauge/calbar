import SwiftUI

/// "Deleted “Design sync”" with Undo, and the seconds left before the
/// deletion reaches Google.
struct UndoBar: View {
    let title: String
    let onUndo: () -> Void
    @State private var started = Date()

    var body: some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            let left = max(0, 10 - Int(context.date.timeIntervalSince(started)))
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text("Deleted \u{201C}\(title)\u{201D}")
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
        .id(title)
    }
}
