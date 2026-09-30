import SwiftUI
import MacalCore

/// Top bar of the popover: the day title with a caption below it, and the
/// previous and next day buttons grouped on the right.
struct DayHeader<Info: View>: View {
    let day: Date
    let isToday: Bool
    let onChange: (Int) -> Void
    let onToday: () -> Void
    @ViewBuilder let info: () -> Info

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                title
                info()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                IconButton("chevron.left", tooltip: "Previous day") { onChange(-1) }
                IconButton("chevron.right", tooltip: "Next day") { onChange(1) }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
    }

    /// Clicking the title of another day goes back to today.
    @ViewBuilder
    private var title: some View {
        let label = Text(DayHeaderText.title(day))
            .font(.system(size: 15, weight: .semibold))
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
}
