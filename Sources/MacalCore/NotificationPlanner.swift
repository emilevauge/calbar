import Foundation

/// When a meeting gets a peek of the popover (`MeetingPeeker`): at most
/// twice per occurrence, once when it enters the alert window (start -
/// lead time), before it starts, and once when it starts.
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

}
