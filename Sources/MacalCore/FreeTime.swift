import Foundation

/// Free time between the events of a list, for the "2 h free" separators.
public enum FreeTime {
    /// Separators shorter than this are not shown.
    public static let minimum: TimeInterval = 30 * 60

    /// Free time before each event, keyed by event id, when it reaches
    /// `minimum`. Measured from the latest end among the events above it,
    /// so an event nested in a longer one opens no gap. `events` in display
    /// order; the first event has no gap.
    public static func gaps(_ events: [CalendarEvent], minimum: TimeInterval = minimum) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        var busyUntil: Date?
        for event in events {
            if let busyUntil {
                let free = event.start.timeIntervalSince(busyUntil)
                if free >= minimum { result[event.id] = free }
            }
            busyUntil = max(busyUntil ?? event.end, event.end)
        }
        return result
    }
}
