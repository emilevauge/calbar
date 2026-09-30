import Foundation

/// English labels for times and durations.
public enum AgendaFormat {
    public static func relative(_ e: CalendarEvent, now: Date) -> String {
        if now >= e.end { return "ended" }
        if now >= e.start { return "now · \(duration(e.end.timeIntervalSince(now))) left" }
        let wait = e.start.timeIntervalSince(now)
        return wait < 60 ? "now" : "in \(duration(wait))"
    }

    /// "35 min left" for an ongoing event, `relative` otherwise.
    public static func remaining(_ e: CalendarEvent, now: Date) -> String {
        if now >= e.start && now < e.end { return "\(duration(e.end.timeIntervalSince(now))) left" }
        return relative(e, now: now)
    }

    /// Rounded up to the minute, so "in 1 min" never shows for a meeting
    /// that already started.
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    public static func timeRange(_ e: CalendarEvent, calendar: Calendar) -> String {
        "\(clock(e.start, calendar))-\(clock(e.end, calendar))"
    }

    /// "3 events", `nil` for none.
    public static func eventCount(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 event"
        default: "\(count) events"
        }
    }

    public static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
