import Foundation

/// Which meetings get a system notification, and what it says. A meeting
/// notifies once per occurrence, when it enters the alert window
/// (start - lead time), and only before it starts.
public enum NotificationPlanner {
    /// Events to notify at `now`, earliest first. `skip` holds the
    /// `occurrenceKey` of occurrences already notified or dismissed.
    public static func due(
        _ events: [CalendarEvent],
        now: Date,
        policy: AlertPolicy,
        skip: Set<String>
    ) -> [CalendarEvent] {
        events
            .filter { e in
                !e.isAllDay
                    && e.selfResponse != .declined
                    && !skip.contains(e.occurrenceKey)
                    && now >= e.start.addingTimeInterval(-policy.leadTime)
                    && now < e.start
            }
            .sorted { ($0.start, $0.occurrenceKey) < ($1.start, $1.occurrenceKey) }
    }

    /// End of the alert window, as in `AlertPlanner.due`: the notification
    /// is withdrawn then, and its key can be forgotten.
    public static func windowEnd(_ e: CalendarEvent, policy: AlertPolicy) -> Date {
        min(e.start.addingTimeInterval(policy.lingerAfterStart), e.end)
    }

    /// "In 5 min · 15:00-16:00", plus " · Zoom" when there is a link.
    public static func body(_ e: CalendarEvent, now: Date, calendar: Calendar) -> String {
        var parts = [
            "In \(AgendaFormat.duration(e.start.timeIntervalSince(now)))",
            AgendaFormat.timeRange(e, calendar: calendar),
        ]
        if let meeting = e.meeting { parts.append(meeting.provider.displayName) }
        return parts.joined(separator: " · ")
    }
}
