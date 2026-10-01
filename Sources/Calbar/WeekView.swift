import SwiftUI
import CalbarCore

/// The week, or one day, as an hour grid: a column per shown day, all-day events on top,
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
    /// 720 pt for the week; the popover's width for one day.
    var width: CGFloat = Self.width
    /// Creating events from a selected slot; none without it.
    var composer: EventComposer?
    static let gutter: CGFloat = 40
    static let hourHeight: CGFloat = 44
    @State private var opened: String?
    /// The slot of a new event while it is dragged out, then while its
    /// editor is open (`editing`).
    @State private var draft: Draft?
    /// When the last editor popover closed: presenting the next one during
    /// its closing animation would be dropped.
    @State private var editorClosedAt = Date.distantPast

    struct Draft {
        let day: Date
        let start: Int
        let end: Int
        let editing: Bool
    }
    /// The all-day row shows every event instead of two per day.
    @State private var allDayUnfolded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            // One day already has its title in the popover header.
            if days.count > 1 {
                dayHeaders
            }
            allDayRow(contents)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    grid(contents)
                }
                .frame(height: CGFloat(max(endHour - startHour, 1)) * Self.hourHeight)
                .onAppear { proxy.scrollTo(startHour, anchor: .top) }
                .onChange(of: startHour) { _, hour in proxy.scrollTo(hour, anchor: .top) }
            }
        }
        .frame(width: width)
    }

    /// Text on the opaque blocks. Not `.secondary`: on the popover's
    /// material it is vibrant, blended with what lies behind the panel
    /// rather than the block, and can vanish.
    static func ink(_ opacity: Double) -> Color {
        Color(nsColor: .labelColor).opacity(opacity)
    }

    private var columnWidth: CGFloat { (width - Self.gutter - 8) / CGFloat(max(days.count, 1)) }

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

    /// All-day events, and timed ones of a day or more, as bars across
    /// the days they cover: two rows, then a "+N" under each day with
    /// hidden bars, which unfolds every row (a chevron folds them back).
    private func allDayRow(_ contents: [DayContent]) -> some View {
        var seen = Set<String>()
        let events = contents.flatMap { content -> [CalendarEvent] in
            if case .loaded(let listing) = content { return listing.allDay + listing.timed.filter(\.spansDays) }
            return []
        }.filter { seen.insert($0.occurrenceKey).inserted }
        let bars = WeekLayout.bars(events, days: days, calendar: .current)
        let rowCount = (bars.map(\.row).max() ?? -1) + 1
        let limit = 2
        let shownRows = allDayUnfolded ? rowCount : min(rowCount, limit)
        let hidden = WeekLayout.hidden(bars, rows: limit, days: days.count)
        let rowHeight: CGFloat = 18
        return Group {
            if !bars.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(height: CGFloat(shownRows) * rowHeight)
                        ForEach(bars.filter { $0.row < shownRows }, id: \.event.occurrenceKey) { bar in
                            allDayBar(bar)
                                .frame(width: CGFloat(bar.last - bar.first + 1) * columnWidth - 4, height: rowHeight - 2)
                                .offset(x: Self.gutter + CGFloat(bar.first) * columnWidth + 2,
                                        y: CGFloat(bar.row) * rowHeight)
                        }
                    }
                    if rowCount > limit {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: Self.gutter, height: 1)
                            ForEach(Array(hidden.enumerated()), id: \.offset) { _, count in
                                moreButton(count)
                                    .frame(width: columnWidth, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    /// "+N" under a day while folded, a chevron on every day while unfolded.
    @ViewBuilder
    private func moreButton(_ count: Int) -> some View {
        if allDayUnfolded || count > 0 {
            Button {
                withAnimation(Motion.resize) { allDayUnfolded.toggle() }
            } label: {
                Group {
                    if allDayUnfolded {
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold))
                    } else {
                        Text("+\(count)")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(minHeight: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(allDayUnfolded ? "Show less" : "Show all")
        } else {
            Color.clear.frame(height: 14)
        }
    }

    /// The title, and the start time of a timed event when it starts this
    /// week: "Trip to Lyon, 08:00".
    private func allDayBar(_ bar: WeekLayout.Bar) -> some View {
        let event = bar.event
        let color = Color(hex: event.colorHex)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let time = !event.isAllDay && !bar.continuesBefore ? ", \(AgendaFormat.clock(event.start, .current))" : ""
        return HStack(spacing: 0) {
            if bar.continuesBefore {
                Image(systemName: "chevron.left").font(.system(size: 7, weight: .bold)).padding(.trailing, 3)
            }
            Text(event.title).fontWeight(.medium)
            Text(time).foregroundStyle(Self.ink(0.6))
            Spacer(minLength: 0)
            if bar.continuesAfter {
                Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold))
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .padding(.horizontal, 5)
        .background {
            shape.fill(Color(nsColor: .textBackgroundColor))
            shape.fill(color.opacity(scheme == .dark ? 0.42 : 0.30))
            shape.strokeBorder(color.opacity(0.55), lineWidth: 0.5)
        }
        .help("\(event.title)\n\(AgendaFormat.timeRange(event, calendar: .current))")
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
            // rather than from the middle of their own bounds. Pressing on
            // it, outside the blocks, and dragging marks out a new event;
            // a plain click makes it 30 minutes.
            (today ? Color.accentColor.opacity(0.04) : Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            // A new selection replaces one being edited.
                            guard composer != nil else { return }
                            let r = NewEvent.range(from: value.startLocation.y / minuteHeight,
                                                   to: value.location.y / minuteHeight,
                                                   dragThreshold: 8 / minuteHeight)
                            draft = Draft(day: day, start: r.start, end: r.end, editing: false)
                        }
                        .onEnded { value in
                            guard let composer else { return }
                            let r = NewEvent.range(from: value.startLocation.y / minuteHeight,
                                                   to: value.location.y / minuteHeight,
                                                   dragThreshold: 8 / minuteHeight)
                            composer.contacts.prepare()
                            let selection = Draft(day: day, start: r.start, end: r.end, editing: false)
                            draft = selection
                            // Wait out a popover still closing (this click may
                            // have closed it), then open the editor.
                            let wait = max(0.05, 0.35 - Date().timeIntervalSince(editorClosedAt))
                            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                                guard let current = draft, current.day == selection.day,
                                      current.start == selection.start, current.end == selection.end else { return }
                                draft = Draft(day: day, start: r.start, end: r.end, editing: true)
                            }
                        }
                )
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
                    // Padding, not offset: an offset moves the drawing but
                    // not the frame a popover anchors on.
                    .padding(.leading, 1 + CGFloat(p.lane) * width)
                    .padding(.top, CGFloat(p.startMinute) * minuteHeight + 1)
            }
            if today {
                nowLine(day, minuteHeight: minuteHeight)
            }
            if let draft, Calendar.current.isDate(draft.day, inSameDayAs: day) {
                ghost(draft, minuteHeight: minuteHeight)
            }
        }
    }

    /// The slot of the event being created, with its form.
    private func ghost(_ draft: Draft, minuteHeight: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let start = draft.day.addingTimeInterval(TimeInterval(draft.start * 60))
        let end = draft.day.addingTimeInterval(TimeInterval(draft.end * 60))
        return shape.fill(Color.accentColor.opacity(0.25))
            .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                Text("\(AgendaFormat.clock(start, .current))-\(AgendaFormat.clock(end, .current))")
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.ink(0.85))
                    .padding(.leading, 5)
                    .padding(.top, 2)
            }
            .frame(width: columnWidth - 3, height: max(CGFloat(draft.end - draft.start) * minuteHeight - 2, 10))
            .allowsHitTesting(false)
            // The editor, in a popover on the slot like an event's card.
            .popover(isPresented: Binding(get: { self.draft?.editing == true }, set: { shown in
                guard !shown else { return }
                self.draft = nil
                editorClosedAt = Date()
            }), arrowEdge: .trailing) {
                if let composer {
                    EventEditor(start: start, end: end, calendars: composer.calendars, contacts: composer.contacts,
                                zoom: composer.zoom, onCreate: composer.create, onDone: { self.draft = nil })
                }
            }
            // After the popover, so it anchors on the slot itself.
            .padding(.leading, 1)
            .padding(.top, CGFloat(draft.start) * minuteHeight + 1)
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
                        .foregroundStyle(Self.ink(0.6))
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 2)
            // A short meeting has just room for its title.
            .padding(.vertical, height < 20 ? 0 : 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: height)
            .background {
                // An opaque base under the tint: on the translucent popover
                // a bare tint mixes with the wallpaper. A hairline in the
                // calendar color keeps neighbors apart. Past and declined
                // events get a lighter tint, not transparency.
                let fill = (scheme == .dark ? 0.42 : 0.30) * (declined ? 0.3 : past ? 0.5 : 1)
                shape.fill(Color(nsColor: .textBackgroundColor))
                if awaits {
                    shape.fill(color.opacity(fill * 0.4))
                    shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    shape.fill(color.opacity(fill))
                    shape.strokeBorder(color.opacity(past || declined ? 0.35 : 0.55), lineWidth: 0.5)
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
        .foregroundStyle(Self.ink(past || declined ? 0.55 : 1))
        .help("\(event.title)\n\(AgendaFormat.timeRange(event, calendar: .current))")
        .popover(isPresented: Binding(get: { opened == event.id }, set: { if !$0 { opened = nil } }),
                 arrowEdge: .trailing) {
            EventRow(event: event, now: now, selected: false, expanded: true, isPast: past,
                     showsRelative: Calendar.current.isDateInToday(event.start), isFocus: true,
                     onToggle: {}, onJoin: { onJoin(event) })
                .frame(width: 360)
                .padding(.vertical, 6)
                // ⌫ in the open card deletes the event (⌘Z in the panel undoes).
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                    let store = AppDelegate.shared.store
                    guard store.canDelete(event) else { NSSound.beep(); return .handled }
                    opened = nil
                    withAnimation(Motion.resize) { store.delete(event) }
                    return .handled
                }
        }
    }
}
