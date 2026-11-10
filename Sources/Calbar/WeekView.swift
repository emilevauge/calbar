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
    /// A slot selected on the grid, by a click or a drag: a new event, or
    /// new times for the one being edited. None: no selecting.
    var onSelect: ((Date, Date) -> Void)?
    /// Days picked on the all-day row, by a click or a drag across days:
    /// the first one, and the day after the last.
    var onSelectAllDay: ((Date, Date) -> Void)?
    /// The event being created or edited beside the grid: its times, and
    /// its guests' availability.
    var slot: Slot?

    struct Slot {
        let start: Date
        let end: Date
        /// The edited event, drawn faded at its old time.
        let eventID: String?
        /// Whole days: drawn on the all-day row, not on the hours.
        var isAllDay = false
        let busy: [String: [DateInterval]]
        let free: [DateInterval]
        /// No guests: no availability to draw.
        let hasGuests: Bool
    }
    /// Finding a time for an event: the guests' busy times and the free
    /// slots drawn on the grid, a click proposing to move it there.
    var availability: Availability?
    /// An editor is about to open: the event card closes first.
    var dismissCards = false

    struct Availability {
        let event: CalendarEvent
        /// Busy times of each person shown, by email.
        let busy: [String: [DateInterval]]
        /// Where the event fits for everyone shown.
        let free: [DateInterval]
        /// Display names by lowercased email.
        let names: [String: String]
        /// Names of the people whose calendar is not shared.
        let unknown: [String]
        /// A click picks a time: to move the event, or to propose.
        let canMove: Bool
        /// Picking proposes the time to the organizer rather than moving.
        let proposes: Bool
        let onMove: (Date, RecurrenceScope) async throws -> Void

        var minutes: Int { max(Int(event.end.timeIntervalSince(event.start) / 60), 15) }
    }
    @AppStorage(Prefs.homeTimeZoneKey) private var homeTimeZone = ""
    /// Home, when away from it in another time zone: each hour also
    /// shows its home time.
    private var home: TimeZone? {
        HomeClock.away(home: homeTimeZone, current: .current, at: days.first ?? Date())
    }
    private var gutter: CGFloat { home == nil ? 40 : 74 }
    static let clockWidth: CGFloat = 32

    /// "NYC PAR" over the hour columns, away from home.
    @ViewBuilder private var zoneTitles: some View {
        if let home {
            HStack(spacing: 4) {
                Text(AirportCode.code(city: nil, zone: .current))
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.clockWidth, alignment: .trailing)
                    .help("Here, \(HomeClock.name(.current, at: Date()))")
                Text(AirportCode.code(city: UserDefaults.standard.string(forKey: Prefs.homeCityKey), zone: home))
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.clockWidth, alignment: .trailing)
                    .help("At home, \(HomeClock.name(home, at: Date()))")
            }
            .font(.caption2)
            .frame(width: gutter - 6, alignment: .trailing)
            .padding(.trailing, 6)
        } else {
            Color.clear.frame(width: gutter)
        }
    }
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
        /// A new time for `availability`'s event, not a new event.
        var moving = false
    }
    /// When the press on the grid began: a click creates nothing, a drag
    /// or a press held `holdDelay` does.
    @State private var pressStart: Date?
    static let holdDelay: TimeInterval = 0.4
    /// The all-day row shows every event instead of two per day.
    @State private var allDayUnfolded = false
    /// Days marked out on the all-day row, as column indices, while dragged.
    @State private var allDayDraft: ClosedRange<Int>?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            // One day already has its title in the popover header.
            if days.count > 1 {
                dayHeaders
            } else if home != nil {
                zoneTitles.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
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
        // Rescheduling and editing start from an event's card: it closes.
        .onChange(of: availability?.event.id) {
            opened = nil
            draft = nil
        }
        .onChange(of: slot != nil) {
            opened = nil
        }
        .onChange(of: dismissCards) { _, dismiss in
            if dismiss { opened = nil }
        }
    }

    /// Text on the opaque blocks. Not `.secondary`: on the popover's
    /// material it is vibrant, blended with what lies behind the panel
    /// rather than the block, and can vanish.
    static func ink(_ opacity: Double) -> Color {
        Color(nsColor: .labelColor).opacity(opacity)
    }

    private var columnWidth: CGFloat { (width - gutter - 8) / CGFloat(max(days.count, 1)) }

    // MARK: headers

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            zoneTitles
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
        let selecting = onSelectAllDay != nil && availability == nil
        // Days of the event being edited, when it is all day.
        let slotDays: ClosedRange<Int>? = slot.flatMap { slot in
            guard slot.isAllDay else { return nil }
            let covered = days.indices.filter { days[$0] < slot.end && slot.start < days[$0].addingTimeInterval(86_400) }
            guard let first = covered.first, let last = covered.last else { return nil }
            return first...last
        }
        let marked = allDayDraft ?? slotDays
        // An empty row stays a row to click on while creating is possible.
        let height = CGFloat(max(shownRows, selecting ? 1 : 0)) * rowHeight
        return Group {
            if !bars.isEmpty || selecting {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(height: height)
                        if selecting {
                            allDayLabel
                        }
                        if let marked {
                            allDayGhost(marked, height: height)
                        }
                        ForEach(bars.filter { $0.row < shownRows }, id: \.event.occurrenceKey) { bar in
                            allDayBar(bar)
                                .frame(width: CGFloat(bar.last - bar.first + 1) * columnWidth - 4, height: rowHeight - 2)
                                .offset(x: gutter + CGFloat(bar.first) * columnWidth + 2,
                                        y: CGFloat(bar.row) * rowHeight)
                        }
                    }
                    if rowCount > limit {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: gutter, height: 1)
                            ForEach(Array(hidden.enumerated()), id: \.offset) { _, count in
                                moreButton(count)
                                    .frame(width: columnWidth, alignment: .leading)
                            }
                        }
                    }
                }
                // Anywhere on the area, folded or not, over the bars and the
                // "+N" row too: only the "+N" buttons keep their clicks.
                .contentShape(Rectangle())
                .gesture(allDaySelection(bars: bars.filter { $0.row < shownRows }, rowHeight: rowHeight), isEnabled: selecting)
                .padding(.bottom, 4)
            }
        }
    }

    /// "all-day" in the gutter, while the area creates events.
    private var allDayLabel: some View {
        Text("all-day")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(width: gutter - 6, height: 16, alignment: .trailing)
            .help("Click or drag across days for an all-day event")
    }

    /// A click on a day, or a drag across days, marks out a new all-day
    /// event over them.
    /// A press on a bar opens its card instead, unless editing.
    private func allDaySelection(bars: [WeekLayout.Bar], rowHeight: CGFloat) -> some Gesture {
        let columns = days.count
        let columnWidth = columnWidth
        func column(_ x: CGFloat) -> Int {
            min(max(Int((x - gutter) / max(columnWidth, 1)), 0), columns - 1)
        }
        let editing = slot != nil
        func onBar(_ point: CGPoint) -> Bool {
            guard !editing, point.x >= gutter else { return false }
            let row = Int(point.y / rowHeight), day = column(point.x)
            return bars.contains { $0.row == row && $0.first <= day && day <= $0.last }
        }
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !onBar(value.startLocation) else { return }
                let a = column(value.startLocation.x)
                let b = column(value.location.x)
                allDayDraft = min(a, b)...max(a, b)
            }
            .onEnded { value in
                allDayDraft = nil
                guard !onBar(value.startLocation) else { return }
                let a = column(value.startLocation.x)
                let b = column(value.location.x)
                let first = days[min(a, b)]
                let last = days[max(a, b)]
                let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
                onSelectAllDay?(first, end)
            }
    }

    /// The days of the all-day event being created or edited.
    private func allDayGhost(_ range: ClosedRange<Int>, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return shape.fill(Color.accentColor.opacity(0.25))
            .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 1))
            .frame(width: CGFloat(range.count) * columnWidth - 4, height: max(height - 2, 16))
            .offset(x: gutter + CGFloat(range.lowerBound) * columnWidth + 2)
            .allowsHitTesting(false)
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
        return Button {
            opened = event.id
        } label: {
            HStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape.fill(Color(nsColor: .textBackgroundColor))
                shape.fill(color.opacity(scheme == .dark ? 0.42 : 0.30))
                shape.strokeBorder(color.opacity(0.55), lineWidth: 0.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // Editing or finding a time: clicks go to the row under it.
        .allowsHitTesting(availability == nil && slot == nil)
        .help(([event.title, AgendaFormat.timeRange(event, calendar: .current)] + [AppDelegate.shared.accounts.calendarName(event)].compactMap { $0 }).joined(separator: "\n"))
        .popover(isPresented: Binding(get: { opened == event.id }, set: { shown in
            guard !shown else { return }
            opened = nil
        }), arrowEdge: .bottom) {
            card(event)
        }
    }

    // MARK: grid

    private func grid(_ contents: [DayContent]) -> some View {
        let hourHeight = Self.hourHeight
        return ZStack(alignment: .topLeading) {
            // Hour lines and labels, each hour an anchor for scrolling.
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 0) {
                        HStack(spacing: 4) {
                            // Where I am on the left, in bold; home beside the grid.
                            Text(String(format: "%02d:00", hour))
                                .fontWeight(home == nil ? .regular : .bold)
                                .foregroundStyle(home == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                                .frame(width: home == nil ? nil : Self.clockWidth, alignment: .trailing)
                            if let home, let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0,
                                                                            of: days.first ?? Date()) {
                                Text(HomeClock.label(date, in: home))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: Self.clockWidth, alignment: .trailing)
                                    .help("At home, \(HomeClock.name(home, at: date))")
                            }
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(width: gutter - 6, alignment: .trailing)
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
                Color.clear.frame(width: gutter)
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
                            if let availability {
                                guard availability.canMove else { return }
                                let start = moveStart(value.location.y / minuteHeight, availability)
                                draft = Draft(day: day, start: start, end: start + availability.minutes,
                                              editing: false, moving: true)
                                return
                            }
                            guard onSelect != nil else { return }
                            let r = NewEvent.range(from: value.startLocation.y / minuteHeight,
                                                   to: value.location.y / minuteHeight,
                                                   dragThreshold: 8 / minuteHeight)
                            let moved = abs(value.location.y - value.startLocation.y) >= 8
                            if pressStart == nil {
                                // A new press: a held one becomes a selection
                                // after a moment, even without moving.
                                let started = Date()
                                pressStart = started
                                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay) {
                                    guard pressStart == started, draft == nil else { return }
                                    draft = Draft(day: day, start: r.start, end: r.end, editing: false)
                                }
                            }
                            // Creating needs a drag or a held press: a plain
                            // click on the grid does nothing. While editing,
                            // a click moves the event at once.
                            if moved || slot != nil || draft != nil {
                                draft = Draft(day: day, start: r.start, end: r.end, editing: false)
                            }
                        }
                        .onEnded { value in
                            if let availability {
                                guard availability.canMove else { return }
                                let start = moveStart(value.location.y / minuteHeight, availability)
                                let selection = Draft(day: day, start: start, end: start + availability.minutes,
                                                      editing: false, moving: true)
                                draft = selection
                                let wait = max(0.05, 0.35 - Date().timeIntervalSince(editorClosedAt))
                                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                                    guard let current = draft, current.moving, current.day == selection.day,
                                          current.start == selection.start else { return }
                                    draft = Draft(day: day, start: start, end: start + availability.minutes,
                                                  editing: true, moving: true)
                                }
                                return
                            }
                            let held = pressStart.map { Date().timeIntervalSince($0) >= Self.holdDelay } ?? false
                            pressStart = nil
                            guard let onSelect else { return }
                            draft = nil
                            if slot == nil, !held, abs(value.location.y - value.startLocation.y) < 8 { return }
                            var r = NewEvent.range(from: value.startLocation.y / minuteHeight,
                                                   to: value.location.y / minuteHeight,
                                                   dragThreshold: 8 / minuteHeight)
                            // A click while editing moves the event, same length.
                            if let slot, abs(value.location.y - value.startLocation.y) < 8 {
                                let minutes = max(Int(slot.end.timeIntervalSince(slot.start) / 60), 15)
                                r = (r.start, min(r.start + minutes, 24 * 60))
                            }
                            onSelect(day.addingTimeInterval(TimeInterval(r.start * 60)),
                                     day.addingTimeInterval(TimeInterval(r.end * 60)))
                        }
                )
            if let availability {
                availabilityLayer(day, busy: availability.busy, free: availability.free, minuteHeight: minuteHeight)
            } else if let slot, slot.hasGuests {
                availabilityLayer(day, busy: slot.busy, free: slot.free, minuteHeight: minuteHeight)
            }
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
                    // Finding a time: the other events step back and let
                    // clicks through to the slots under them.
                    .opacity(availability.map { $0.event.id == p.event.id ? 1 : 0.3 }
                             ?? slot.map { $0.eventID == p.event.id ? 0.35 : 0.45 } ?? 1)
                    .allowsHitTesting(availability == nil && slot == nil)
                    .overlay {
                        if availability?.event.id == p.event.id || (slot != nil && slot?.eventID == p.event.id) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                                .allowsHitTesting(false)
                        }
                    }
                    // Padding, not offset: an offset moves the drawing but
                    // not the frame a popover anchors on.
                    .padding(.leading, 1 + CGFloat(p.lane) * width)
                    .padding(.top, CGFloat(p.startMinute) * minuteHeight + 1)
            }
            if today {
                nowLine(day, minuteHeight: minuteHeight)
            }
            // An all-day event has no slot on the hours.
            if let slot, draft == nil, !slot.isAllDay, slot.end.timeIntervalSince(slot.start) < 86_400,
               Calendar.current.isDate(slot.start, inSameDayAs: day) {
                slotGhost(slot, day: day, minuteHeight: minuteHeight)
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
        // A new time is green where everyone is free, orange otherwise.
        let tint: Color = draft.moving
            ? (availability.map { FreeBusy.conflicts(DateInterval(start: start, end: end), busy: $0.busy).isEmpty } == true
                ? .green : .orange)
            : .accentColor
        return shape.fill(tint.opacity(0.25))
            .overlay(shape.strokeBorder(tint, lineWidth: 1))
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
                if draft.moving, let availability {
                    let slot = DateInterval(start: start, end: end)
                    MoveConfirm(event: availability.event, proposes: availability.proposes, start: start, end: end,
                                busy: FreeBusy.conflicts(slot, busy: availability.busy).map { availability.names[$0] ?? FindTimeBar.firstName(Person(email: $0, name: nil)) },
                                unknown: availability.unknown,
                                onMove: { scope in
                                    try await availability.onMove(start, scope)
                                    self.draft = nil
                                },
                                onCancel: { self.draft = nil })
                }
            }
            // After the popover, so it anchors on the slot itself.
            .padding(.leading, 1)
            .padding(.top, CGFloat(draft.start) * minuteHeight + 1)
    }

    /// Red line at the current time, with a dot on the left.
    /// The event being edited beside the grid, at its new times: green
    /// when every guest is free, orange otherwise, blue without guests.
    private func slotGhost(_ slot: Slot, day: Date, minuteHeight: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let startMinute = slot.start.timeIntervalSince(Calendar.current.startOfDay(for: day)) / 60
        let length = max(slot.end.timeIntervalSince(slot.start) / 60, 15)
        let tint: Color = !slot.hasGuests ? .accentColor
            : FreeBusy.conflicts(DateInterval(start: slot.start, end: slot.end), busy: slot.busy).isEmpty ? .green : .orange
        return shape.fill(tint.opacity(0.3))
            .overlay(shape.strokeBorder(tint, lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                Text("\(AgendaFormat.clock(slot.start, .current))-\(AgendaFormat.clock(slot.end, .current))")
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.ink(0.9))
                    .padding(.leading, 5)
                    .padding(.top, 2)
            }
            .frame(width: columnWidth - 3, height: max(CGFloat(length) * minuteHeight - 2, 10))
            .allowsHitTesting(false)
            .padding(.leading, 1)
            .padding(.top, CGFloat(startMinute) * minuteHeight + 1)
    }

    /// The start of the moved event under the pointer: to the quarter
    /// hour, the event ending by midnight.
    private func moveStart(_ minute: Double, _ availability: Availability) -> Int {
        let m = Int(minute.rounded(.down))
        return min(max(m - m % 15, 0), 24 * 60 - availability.minutes)
    }

    /// Busy times hatched, darker where several people are busy, and the
    /// free slots in green, marked "Free".
    private func availabilityLayer(_ day: Date, busy: [String: [DateInterval]], free freeSlots: [DateInterval],
                                   minuteHeight: CGFloat) -> some View {
        let midnight = Calendar.current.startOfDay(for: day)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400)
        func minutes(_ span: DateInterval) -> (Double, Double)? {
            guard span.end > midnight, span.start < next else { return nil }
            return (max(span.start, midnight).timeIntervalSince(midnight) / 60,
                    min(span.end, next).timeIntervalSince(midnight) / 60)
        }
        let each = busy.values.flatMap { $0 }.compactMap(minutes)
        let any = FreeBusy.union(busy.values.flatMap { $0 }).compactMap(minutes)
        let free = freeSlots.compactMap(minutes)
        let width = columnWidth - 1
        return ZStack(alignment: .topLeading) {
            ForEach(Array(each.enumerated()), id: \.offset) { _, span in
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: width, height: CGFloat(span.1 - span.0) * minuteHeight)
                    .padding(.top, CGFloat(span.0) * minuteHeight)
            }
            ForEach(Array(any.enumerated()), id: \.offset) { _, span in
                Hatching()
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    .frame(width: width, height: CGFloat(span.1 - span.0) * minuteHeight)
                    .clipped()
                    .padding(.top, CGFloat(span.0) * minuteHeight)
            }
            ForEach(Array(free.enumerated()), id: \.offset) { _, span in
                let height = CGFloat(span.1 - span.0) * minuteHeight
                Rectangle()
                    .fill(Color.green.opacity(scheme == .dark ? 0.32 : 0.26))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.green).frame(width: 3) }
                    .overlay(alignment: .topLeading) {
                        if height > 16 {
                            Text("Free")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.green)
                                .brightness(scheme == .dark ? 0.1 : -0.25)
                                .padding(.leading, 6)
                                .padding(.top, 2)
                        }
                    }
                    .frame(width: width, height: height)
                    .padding(.top, CGFloat(span.0) * minuteHeight)
            }
        }
        .allowsHitTesting(false)
    }

    private func nowLine(_ day: Date, minuteHeight: CGFloat) -> some View {
        let minutes = now.timeIntervalSince(Calendar.current.startOfDay(for: day)) / 60
        return HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
        .offset(x: -3.5, y: CGFloat(minutes) * minuteHeight - 3.5)
        .allowsHitTesting(false)
    }

    /// An event's card, in a popover from its block or bar.
    private func card(_ event: CalendarEvent) -> some View {
        EventRow(event: event, now: now, selected: false, expanded: true, isPast: event.end <= now,
                 showsRelative: Calendar.current.isDateInToday(event.start), isFocus: true,
                 onToggle: {}, onJoin: { onJoin(event) })
            .frame(width: 360)
            .padding(.vertical, 6)
            // ⌫ in the open card deletes the event (⌘Z in the panel undoes).
            .focusable()
            .focusEffectDisabled()
            .onKeyPress { press in
                let store = AppDelegate.shared.store
                guard MenuView.isDeleteKey(press), store.composing == nil else { return .ignored }
                guard store.canDelete(event) else { NSSound.beep(); return .handled }
                opened = nil
                withAnimation(Motion.resize) { store.deleteFromKey(event) }
                return .handled
            }
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
                    // The calendar after the time, cut when too long.
                    HStack(spacing: 4) {
                        Text(AgendaFormat.clock(event.start, .current))
                            .monospacedDigit()
                            .layoutPriority(1)
                        if let name = AppDelegate.shared.accounts.calendarName(event) {
                            Text(name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .font(.system(size: 9.5))
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
        .help(([event.title, AgendaFormat.timeRange(event, calendar: .current)] + [AppDelegate.shared.accounts.calendarName(event)].compactMap { $0 }).joined(separator: "\n"))
        .popover(isPresented: Binding(get: { opened == event.id }, set: { shown in
            guard !shown else { return }
            opened = nil
        }),
                 arrowEdge: .trailing) {
            card(event)
        }
    }
}

/// Diagonal lines every 6 points, for busy times.
private struct Hatching: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 6
        }
        return path
    }
}
