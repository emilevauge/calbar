import Foundation

/// Which meetings get a system notification, and what it says. A meeting
/// notifies at most twice per occurrence: once when it enters the alert
/// window (start - lead time), before it starts, and once when it starts.
public enum NotificationPlanner {
    public enum Stage: Sendable {
        /// In the alert window, before the start.
        case soon
        /// From the start to the end of the alert window.
        case starting
    }

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

    /// Events whose start notification is due at `now`, earliest first:
    /// started, alert window not over. `skip` holds the `occurrenceKey` of
    /// occurrences whose start was already notified, or dismissed.
    public static func dueAtStart(
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
                    && now >= e.start
                    && now < windowEnd(e, policy: policy)
            }
            .sorted { ($0.start, $0.occurrenceKey) < ($1.start, $1.occurrenceKey) }
    }

    /// End of the alert window, as in `AlertPlanner.due`: the notification
    /// is withdrawn then, and its key can be forgotten.
    public static func windowEnd(_ e: CalendarEvent, policy: AlertPolicy) -> Date {
        min(e.start.addingTimeInterval(policy.lingerAfterStart), e.end)
    }

    /// "Zoom · 15:00-16:00", or the time range alone without a link.
    public static func subtitle(_ e: CalendarEvent, calendar: Calendar) -> String {
        let range = AgendaFormat.timeRange(e, calendar: calendar)
        guard let meeting = e.meeting else { return range }
        return "\(meeting.provider.displayName) · \(range)"
    }

    /// "In 5 min", then from the start "Starting now" or "Started 3 min
    /// ago"; followed by the place (unless it is a URL), the guests and the
    /// attached documents: "In 5 min · Room 4 · 6 guests · 2 docs".
    public static func body(_ e: CalendarEvent, now: Date) -> String {
        var parts = [when(e, now: now)]
        if let place = e.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !place.isEmpty, !place.lowercased().hasPrefix("http") {
            parts.append(place)
        }
        if e.attendees.count > 1 { parts.append("\(e.attendees.count) guests") }
        switch e.attachments.count {
        case 0: break
        case 1: parts.append("1 doc")
        case let n: parts.append("\(n) docs")
        }
        return parts.joined(separator: " · ")
    }

    private static func when(_ e: CalendarEvent, now: Date) -> String {
        let ahead = e.start.timeIntervalSince(now)
        if ahead > 0 { return "In \(AgendaFormat.duration(ahead))" }
        if -ahead < 60 { return "Starting now" }
        return "Started \(Int(-ahead / 60)) min ago"
    }
}
