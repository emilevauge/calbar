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

/// All-day events as small colored chips on one line, above the timed
/// ones. Chips that do not fit fold into a "+N" chip, which unfolds them
/// all on wrapped lines.
struct AllDayStrip: View {
    let events: [CalendarEvent]
    @State private var width: CGFloat = 0
    @State private var unfolded = false

    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let spacing: CGFloat = 4

    var body: some View {
        let shown = unfolded ? events.count : Self.fitting(events, in: width)
        FlowLayout(spacing: Self.spacing, lineSpacing: Self.spacing) {
            ForEach(events.prefix(shown)) { event in
                chip(event)
            }
            if shown < events.count {
                moreChip(events.count - shown)
            } else if unfolded {
                lessChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { width = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, new in width = new }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func chip(_ event: CalendarEvent) -> some View {
        let color = Color(hex: event.colorHex)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(event.title)
                .lineLimit(1)
        }
        .font(Font(Self.font))
        .padding(.horizontal, Self.padding)
        .frame(height: 18)
        .background(color.opacity(0.14), in: Capsule())
        .help(event.title)
    }

    private func moreChip(_ count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { unfolded = true }
        } label: {
            Text("+\(count)")
                .font(Font(Self.font))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Self.padding)
                .frame(height: 18)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(events.suffix(count).map(\.title).joined(separator: "\n"))
    }

    private var lessChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { unfolded = false }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show less")
    }

    private static let padding: CGFloat = 7

    /// Width of a chip: padding, dot, gap, title.
    private static func chipWidth(_ title: String) -> CGFloat {
        let text = (title as NSString).size(withAttributes: [.font: font]).width
        return padding * 2 + 5 + 4 + ceil(text)
    }

    /// How many chips fit on one line, keeping room for "+N" when some
    /// are left over. All of them before the width is known.
    static func fitting(_ events: [CalendarEvent], in width: CGFloat) -> Int {
        guard width > 0 else { return events.count }
        let widths = events.map { chipWidth($0.title) }
        if widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0)) <= width {
            return events.count
        }
        let more = padding * 2 + ceil(("+\(events.count)" as NSString).size(withAttributes: [.font: font]).width)
        var used = more
        var count = 0
        for w in widths {
            if used + spacing + w > width { break }
            used += spacing + w
            count += 1
        }
        return count
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
