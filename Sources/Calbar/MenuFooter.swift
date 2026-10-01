import SwiftUI
import AppKit

/// Bottom bar of the popover: refresh, Google Calendar, settings, quit. Every button has
/// the same fixed frame and the row the same height, so the popover
/// anchor on the gear and the dimmed refresh button do not move the
/// glyphs.
struct MenuFooter<Settings: View>: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void
    /// Google Calendar home, pinned to the first connected account.
    let calendarURL: URL
    @ViewBuilder let settings: () -> Settings

    @State private var showingSettings = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            IconButton("arrow.clockwise", tooltip: "Refresh", action: onRefresh)
                .keyboardShortcut("r")
                .disabled(isRefreshing)

            IconButton(tooltip: "Open Google Calendar") {
                NSWorkspace.shared.open(calendarURL)
            } label: {
                GoogleCalendarIcon(size: 14)
                    .foregroundStyle(.secondary)
            }

            IconButton("gearshape", tooltip: "Settings") {
                showingSettings.toggle()
            }
            .keyboardShortcut(",")
            .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
                settings()
            }

            Spacer()

            IconButton("power", tooltip: "Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .frame(height: IconButton<IconGlyph>.size.height)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
