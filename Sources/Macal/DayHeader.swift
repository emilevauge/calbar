import SwiftUI
import MacalCore

/// Top bar of the popover: previous day, day title, next day, and a
/// caption on the right.
struct DayHeader<Info: View>: View {
    let day: Date
    let isToday: Bool
    let onChange: (Int) -> Void
    let onToday: () -> Void
    @ViewBuilder let info: () -> Info

    var body: some View {
        HStack(spacing: 0) {
            IconButton("chevron.left", tooltip: "Previous day") { onChange(-1) }
            title
            IconButton("chevron.right", tooltip: "Next day") { onChange(1) }
            Spacer(minLength: 8)
            info()
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
    }

    /// Fixed width, sized on the widest date, so the chevrons stay put
    /// while clicking through days. Clicking it goes back to today.
    @ViewBuilder
    private var title: some View {
        let label = ZStack {
            Text(DayHeaderText.widest).hidden()
            Text(DayHeaderText.title(day))
        }
        .font(.headline)
        .lineLimit(1)
        if isToday {
            label
        } else {
            Button(action: onToday) {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to today")
        }
    }
}

extension DayHeader where Info == Text? {
    /// Caption for a day other than today: "Tomorrow · 3 events", or
    /// whichever part applies.
    static func otherDayInfo(_ content: DayContent, offset: Int) -> Text? {
        let count: String? = if case .loaded(let listing) = content { AgendaFormat.eventCount(listing.count) } else { nil }
        let parts = [DayWindow.relativeName(offset: offset), count].compactMap { $0 }
        return parts.isEmpty ? nil : Text(parts.joined(separator: " · "))
    }
}

enum DayHeaderText {
    /// "Tuesday, September 29", in English whatever the system locale.
    static func title(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Locale(identifier: "en_US")))
    }

    /// Widest title of the year in the headline font, measured over every day.
    static let widest = "Wednesday, September 30"
}
