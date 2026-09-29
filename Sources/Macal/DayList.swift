import SwiftUI
import MacalCore

/// Events of a day other than today: all-day strip, then every timed
/// event in order. Nothing dimmed, nothing kept open, one row expanded
/// at a time.
struct DayList: View {
    let content: DayContent
    let now: Date
    let selectedIndex: Int
    let expandedID: String?
    let onToggle: (Int, CalendarEvent) -> Void
    let onJoin: (CalendarEvent) -> Void
    let onRetry: () -> Void

    var body: some View {
        switch content {
        case .loading:
            LoadingRow()
        case .failed:
            HStack(spacing: 8) {
                Text("Could not load this day")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        case .loaded(let listing):
            if !listing.allDay.isEmpty {
                AllDayStrip(events: listing.allDay)
            }
            if listing.timed.isEmpty {
                Text(listing.isEmpty ? "No events" : "No timed events")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            ForEach(Array(listing.timed.enumerated()), id: \.element.id) { index, event in
                EventRow(
                    event: event,
                    now: now,
                    selected: index == selectedIndex,
                    expanded: expandedID == event.id,
                    isPast: false,
                    showsRelative: false,
                    onToggle: { onToggle(index, event) },
                    onJoin: { onJoin(event) }
                )
                .id(event.id)
            }
        }
    }
}

/// All-day events as a compact list of colored titles, above the timed ones.
struct AllDayStrip: View {
    let events: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(events) { event in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: event.colorHex))
                        .frame(width: 7, height: 7)
                    Text(event.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
