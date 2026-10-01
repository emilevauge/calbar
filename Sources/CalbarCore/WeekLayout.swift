import Foundation

/// The days of a week and where events sit in the hour grid of the week
/// view.
public enum WeekLayout {
    /// Start of each of the 7 days of the week containing `date`, from the
    /// calendar's first weekday.
    public static func days(containing date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -back, to: day) ?? day
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: first) ?? first }
    }

    /// The days of that week whose weekday (1 = Sunday ... 7 = Saturday,
    /// as `Calendar`) is in `shown`. All of them when `shown` is empty, so
    /// the view never goes blank.
    public static func days(containing date: Date, calendar: Calendar, shown: Set<Int>) -> [Date] {
        let all = days(containing: date, calendar: calendar)
        let kept = all.filter { shown.contains(calendar.component(.weekday, from: $0)) }
        return kept.isEmpty ? all : kept
    }

    /// Weekdays from a setting such as "23456" (Monday to Friday).
    public static func weekdays(_ setting: String) -> Set<Int> {
        Set(setting.compactMap { $0.wholeNumberValue }.filter { (1...7).contains($0) })
    }

    /// "Sep 28 - Oct 4", or "Oct 5 - 11" within one month; the year is
    /// added when the week is not in the current one.
    public static func title(_ days: [Date], now: Date, calendar: Calendar) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let english = Locale(identifier: "en_US")
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let start = first.formatted(.dateTime.month(.abbreviated).day().locale(english))
        let end = sameMonth
            ? last.formatted(.dateTime.day().locale(english))
            : last.formatted(.dateTime.month(.abbreviated).day().locale(english))
        var text = "\(start) - \(end)"
        if calendar.component(.year, from: last) != calendar.component(.year, from: now) {
            text += ", \(calendar.component(.year, from: last))"
        }
        return text
    }

    /// An event in a day column: minutes from midnight, clipped to the
    /// day, and its lane among the events it overlaps.
    public struct Placement: Equatable, Sendable {
        public let event: CalendarEvent
        public let startMinute: Int
        public let endMinute: Int
        /// 0-based lane, and the number of lanes of its group.
        public let lane: Int
        public let lanes: Int
    }

    /// Timed events of `day`, except those lasting a day or more, which go
    /// with the all-day events. Side by side where they overlap: each group
    /// of overlapping events splits the column into as many lanes as it
    /// needs at most, and each event takes the first free lane.
    public static func place(_ events: [CalendarEvent], day: Date, calendar: Calendar) -> [Placement] {
        let window = DayWindow.interval(for: day, calendar: calendar)
        let timed = events
            .filter { !$0.isAllDay && !$0.spansDays && DayWindow.contains($0, in: window) }
            .map { e -> (CalendarEvent, Int, Int) in
                let start = max(e.start, window.start)
                let end = min(max(e.end, e.start), window.end)
                let s = Int(start.timeIntervalSince(window.start) / 60)
                // A zero-length event still takes a sliver of the grid.
                let f = max(Int(end.timeIntervalSince(window.start) / 60), s + 1)
                return (e, s, f)
            }
            .sorted { ($0.1, $1.2, $0.0.id) < ($1.1, $0.2, $1.0.id) }

        var result: [Placement] = []
        var group: [(CalendarEvent, Int, Int, Int)] = []
        var laneEnds: [Int] = []
        var groupEnd = -1

        func flush() {
            let count = laneEnds.count
            result += group.map { Placement(event: $0.0, startMinute: $0.1, endMinute: $0.2, lane: $0.3, lanes: count) }
            group = []
            laneEnds = []
        }

        for (event, start, end) in timed {
            if start >= groupEnd, !group.isEmpty { flush() }
            let lane = laneEnds.firstIndex { $0 <= start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            group.append((event, start, end, lane))
            groupEnd = max(groupEnd, end)
        }
        flush()
        return result
    }
}

extension WeekLayout {
    /// An all-day event, or a timed one of a day or more, as one bar over
    /// the days it covers in the week: `first` and `last` are column
    /// indices, `row` its line in the all-day area.
    public struct Bar: Equatable, Sendable {
        public let event: CalendarEvent
        public let first: Int
        public let last: Int
        public let row: Int
        /// It started before the week, or ends after it.
        public let continuesBefore: Bool
        public let continuesAfter: Bool
    }

    /// Bars for `events` over `days`, each on the first row where it fits:
    /// longer and earlier bars first, so a trip stays on top.
    public static func bars(_ events: [CalendarEvent], days: [Date], calendar: Calendar) -> [Bar] {
        let windows = days.map { DayWindow.interval(for: $0, calendar: calendar) }
        let spans: [(CalendarEvent, Int, Int)] = events
            .filter { $0.isAllDay || $0.spansDays }
            .compactMap { e in
                let covered = windows.indices.filter { DayWindow.contains(e, in: windows[$0]) }
                guard let first = covered.first, let last = covered.last else { return nil }
                return (e, first, last)
            }
            .sorted { ($0.1, $1.2 - $1.1, $0.0.id) < ($1.1, $0.2 - $0.1, $1.0.id) }
        var rows: [[ClosedRange<Int>]] = []
        return spans.map { e, first, last in
            let range = first...last
            let row = rows.firstIndex { taken in !taken.contains { $0.overlaps(range) } } ?? rows.count
            if row == rows.count { rows.append([]) }
            rows[row].append(range)
            return Bar(event: e, first: first, last: last, row: row,
                       continuesBefore: e.start < (windows.first?.start ?? e.start),
                       continuesAfter: e.end > (windows.last?.end ?? e.end))
        }
    }

    /// Bars past `limit` rows, counted per day, for the "+N" of each day.
    public static func hidden(_ bars: [Bar], rows limit: Int, days: Int) -> [Int] {
        (0..<days).map { day in bars.filter { $0.row >= limit && $0.first <= day && day <= $0.last }.count }
    }
}

extension CalendarEvent {
    /// A timed event of 24 hours or more, a trip or a conference: the week
    /// view shows it with the all-day events, like Google Calendar.
    public var spansDays: Bool {
        !isAllDay && end.timeIntervalSince(start) >= 24 * 60 * 60
    }
}
