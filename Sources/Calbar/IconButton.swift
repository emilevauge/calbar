import SwiftUI

/// Borderless icon button with a fixed frame, shared by the popover header
/// and footer so every glyph gets the same hit area.
struct IconButton<Label: View>: View {
    static var size: CGSize { CGSize(width: 28, height: 24) }

    let tooltip: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(tooltip: String, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.tooltip = tooltip
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: Self.size.width, height: Self.size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: Self.size.width, height: Self.size.height)
        .help(tooltip)
    }
}

extension IconButton where Label == IconGlyph {
    init(_ systemName: String, tooltip: String, action: @escaping () -> Void) {
        self.init(tooltip: tooltip, action: action) { IconGlyph(systemName: systemName) }
    }
}

/// SF Symbol in the secondary style of the popover chrome.
struct IconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
