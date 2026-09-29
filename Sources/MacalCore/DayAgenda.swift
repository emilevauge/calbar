import Foundation

/// What the popover shows for the current day.
public struct DayAgenda: Equatable, Sendable {
    public let allDay: [CalendarEvent]
    /// Timed events of today not finished yet, ongoing ones first.
    public let current: [CalendarEvent]
    /// Timed events of today already over, shown dimmed.
    public let past: [CalendarEvent]
    /// Shown once the day is over.
    public let firstTomorrow: CalendarEvent?

    public static func build(from events: [CalendarEvent], now: Date, calendar: Calendar) -> DayAgenda {
        let window = DayWindow.interval(for: now, calendar: calendar)
        let tomorrow = DayWindow.interval(for: window.end, calendar: calendar)
        let sorted = events.sorted { $0.start < $1.start }
        let today = sorted.filter { DayWindow.contains($0, in: window) }
        // A zero-length event is over only once `now` has passed its start.
        let isCurrent = { (e: CalendarEvent) in e.end > now || (e.start == e.end && e.start >= now) }
        return DayAgenda(
            allDay: today.filter(\.isAllDay),
            current: today.filter { !$0.isAllDay && isCurrent($0) },
            past: today.filter { !$0.isAllDay && !isCurrent($0) },
            firstTomorrow: sorted.first { !$0.isAllDay && $0.start >= tomorrow.start && $0.start < tomorrow.end }
        )
    }
}
