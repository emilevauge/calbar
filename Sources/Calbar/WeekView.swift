import SwiftUI
import CalbarCore

/// The week as an hour grid: a column per day, all-day events on top,
/// timed events as blocks placed by `WeekLayout`. The hours from
/// `startHour` to `endHour` fill the visible height; the rest of the day
/// is a scroll away.
struct WeekView: View {
    let days: [Date]
    /// One per day of `days`.
    let contents: [DayContent]
    let now: Date
    let startHour: Int
    let endHour: Int
    /// A click on a day's header shows that day in the day view.
    let onShowDay: (Date) -> Void
    let onJoin: (CalendarEvent) -> Void

    static let width: CGFloat = 720
    static let gutter: CGFloat = 40
    static let hourHeight: CGFloat = 44
    @State private var opened: String?
    /// The all-day row shows every event instead of two per day.
    @State private var allDayUnfolded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            dayHeaders
            allDayRow(contents)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    grid(contents)
                }
                // Opaque: on the translucent popover the light blocks
                // blended into whatever was behind it.
                .background(Color(nsColor: .textBackgroundColor).opacity(scheme == .dark ? 0.55 : 0.85))
                .frame(height: CGFloat(max(endHour - startHour, 1)) * Self.hourHeight)
                .onAppear { proxy.scrollTo(startHour, anchor: .top) }
                .onChange(of: startHour) { _, hour in proxy.scrollTo(hour, anchor: .top) }
            }
        }
        .frame(width: Self.width)
    }

    private var columnWidth: CGFloat { (Self.width - Self.gutter - 8) / 7 }

    // MARK: headers

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(days, id: \.self) { day in
                let today = Calendar.current.isDateInToday(day)
                Button { onShowDay(day) } label: {
                    HStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US"))))
                            .foregroundStyle(.secondary)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .fontWeight(.semibold)
                            .foregroundStyle(today ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .frame(minWidth: 20, minHeight: 20)
                            .background { if today { Circle().fill(Color.accentColor) } }
                    }
                    .font(.caption)
                    .frame(width: columnWidth, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show this day")
            }
        }
        .padding(.top, 4)
    }

    /// All-day events, and timed ones of a day or more: two per day, then
    /// "+N", which unfolds the whole row.
    private func allDayRow(_ contents: [DayContent]) -> some View {
        let lists = contents.map { content -> [CalendarEvent] in
            if case .loaded(let listing) = content { return listing.allDay + listing.timed.filter(\.spansDays) }
            return []
        }
        let foldable = lists.contains { $0.count > 2 }
        return Group {
            if lists.contains(where: { !$0.isEmpty }) {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: Self.gutter, height: 1)
                    ForEach(Array(lists.enumerated()), id: \.offset) { _, events in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(allDayUnfolded ? events : Array(events.prefix(2))) { event in
                                allDayChip(event)
                            }
                            if events.count > 2 {
                                Button {
                                    withAnimation(Motion.resize) { allDayUnfolded.toggle() }
                                } label: {
                                    Group {
                                        if allDayUnfolded {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 8, weight: .semibold))
                                        } else {
                                            Text("+\(events.count - 2)")
                                        }
                                    }
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(allDayUnfolded ? "Show less" : events.dropFirst(2).map(\.title).joined(separator: "\n"))
                            }
                        }
                        .frame(width: columnWidth - 4, alignment: .leading)
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.bottom, foldable ? 2 : 4)
            }
        }
    }

    private func allDayChip(_ event: CalendarEvent) -> some View {
        let color = Color(hex: event.colorHex)
        return Text(event.title)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .help(event.title)
    }

    // MARK: grid

    private func grid(_ contents: [DayContent]) -> some View {
        let hourHeight = Self.hourHeight
        return ZStack(alignment: .topLeading) {
            // Hour lines and labels, each hour an anchor for scrolling.
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 0) {
                        Text(String(format: "%02d:00", hour))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: Self.gutter - 6, alignment: .trailing)
                            // Under its line, so the first visible hour is not cut.
                            .padding(.top, 2)
                        VStack { Divider() }
                            .padding(.leading, 6)
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .id(hour)
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.gutter)
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    column(day, content: contents[index])
                        .frame(width: columnWidth, height: hourHeight * 24, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
                        }
                }
            }
        }
    }

    private func column(_ day: Date, content: DayContent) -> some View {
        let events: [CalendarEvent] = if case .loaded(let listing) = content { listing.timed } else { [] }
        let placements = WeekLayout.place(events, day: day, calendar: .current)
        let minuteHeight = Self.hourHeight / 60
        let today = Calendar.current.isDateInToday(day)
        return ZStack(alignment: .topLeading) {
            // Fills the column, so the blocks are offset from its top
            // rather than from the middle of their own bounds.
            (today ? Color.accentColor.opacity(0.04) : Color.clear)
            if case .loading = content {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .offset(y: CGFloat(startHour) * Self.hourHeight + 8)
            }
            ForEach(placements, id: \.event.id) { p in
                let width = (columnWidth - 3) / CGFloat(p.lanes)
                // 1 pt inset all round: back-to-back blocks get a gap.
                block(p, height: max(CGFloat(p.endMinute - p.startMinute) * minuteHeight - 2, 14))
                    .frame(width: width - 2)
                    .offset(x: 1 + CGFloat(p.lane) * width, y: CGFloat(p.startMinute) * minuteHeight + 1)
            }
            if today {
                nowLine(day, minuteHeight: minuteHeight)
            }
        }
    }

    /// Red line at the current time, with a dot on the left.
    private func nowLine(_ day: Date, minuteHeight: CGFloat) -> some View {
        let minutes = now.timeIntervalSince(Calendar.current.startOfDay(for: day)) / 60
        return HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
        .offset(x: -3.5, y: CGFloat(minutes) * minuteHeight - 3.5)
        .allowsHitTesting(false)
    }

    private func block(_ p: WeekLayout.Placement, height: CGFloat) -> some View {
        let event = p.event
        let color = Color(hex: event.colorHex)
        let declined = event.selfResponse == .declined
        let awaits = event.canRespond && event.selfResponse == .needsAction
        let past = event.end <= now
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return Button {
            opened = event.id
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .strikethrough(declined)
                    // Side by side, a lane is too narrow to wrap: words
                    // would break in the middle.
                    .lineLimit(height > 30 && p.lanes == 1 ? 2 : 1)
                if height > 30 {
                    Text(AgendaFormat.clock(event.start, .current))
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: height)
            .background {
                // Denser than the list's tints, with a hairline in the
                // calendar color, so neighbors stay apart on the grid.
                let fill = scheme == .dark ? 0.42 : 0.30
                if awaits {
                    shape.fill(color.opacity(fill * 0.4))
                    shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    shape.fill(color.opacity(declined ? fill * 0.3 : fill))
                    shape.strokeBorder(color.opacity(0.55), lineWidth: 0.5)
                }
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(color.opacity(declined ? 0.4 : 1)).frame(width: 2.5)
                    .clipShape(shape)
            }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(declined ? 0.55 : past ? 0.7 : 1)
        .help("\(event.title)\n\(AgendaFormat.timeRange(event, calendar: .current))")
        .popover(isPresented: Binding(get: { opened == event.id }, set: { if !$0 { opened = nil } }),
                 arrowEdge: .trailing) {
            EventRow(event: event, now: now, selected: false, expanded: true, isPast: past,
                     showsRelative: Calendar.current.isDateInToday(event.start), isFocus: true,
                     onToggle: {}, onJoin: { onJoin(event) })
                .frame(width: 360)
                .padding(.vertical, 6)
        }
    }
}
