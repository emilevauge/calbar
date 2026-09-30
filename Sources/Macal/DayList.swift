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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        case .loaded(let listing):
            if !listing.allDay.isEmpty {
                AllDayStrip(events: listing.allDay)
            }
            if listing.timed.isEmpty {
                Text(listing.isEmpty ? "No events" : "No timed events")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            let gaps = FreeTime.gaps(listing.timed)
            ForEach(Array(listing.timed.enumerated()), id: \.element.id) { index, event in
                if let gap = gaps[event.id] {
                    FreeGap(interval: gap)
                }
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

/// All-day events as colored chips, above the timed ones.
struct AllDayStrip: View {
    let events: [CalendarEvent]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(events) { event in
                let color = Color(hex: event.colorHex)
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(event.title)
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(color.opacity(0.14), in: Capsule())
                .help(event.title)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

/// "2 h free" between two events far enough apart, lined up with the
/// color bars of the rows.
struct FreeGap: View {
    let interval: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: EventRow.timeColumnWidth)
            VStack { Divider() }.frame(width: 14)
            Text("\(AgendaFormat.duration(interval)) free")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            VStack { Divider() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 1)
    }
}
