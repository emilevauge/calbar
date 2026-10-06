import Foundation

/// Which meetings of today the menu bar icon talks about.
public enum NextMeeting {
    /// Earliest timed, not declined event starting after `now` and before
    /// the end of today. Ongoing meetings are skipped.
    public static func find(events: [CalendarEvent], now: Date, calendar: Calendar) -> CalendarEvent? {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return events
            .filter { !$0.isWholeDay && $0.selfResponse != .declined && $0.start > now && $0.start < dayEnd }
            .min { $0.start < $1.start }
    }

    /// Timed, not declined meeting running at `now`. With several, the one
    /// that ends first.
    public static func ongoing(events: [CalendarEvent], now: Date) -> CalendarEvent? {
        events
            .filter { !$0.isWholeDay && $0.selfResponse != .declined && $0.start <= now && now < $0.end }
            .min { $0.end < $1.end }
    }

    /// Meeting the popover keeps expanded: the ongoing one if any,
    /// otherwise the next one of today.
    public static func focus(events: [CalendarEvent], now: Date, calendar: Calendar) -> CalendarEvent? {
        ongoing(events: events, now: now) ?? find(events: events, now: now, calendar: calendar)
    }
}
