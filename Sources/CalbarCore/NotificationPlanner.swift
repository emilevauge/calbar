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
                !e.isWholeDay
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
                !e.isWholeDay
                    && e.selfResponse != .declined
                    && !skip.contains(e.occurrenceKey)
                    && now >= e.start
                    && now < windowEnd(e, policy: policy)
            }
            .sorted { ($0.start, $0.occurrenceKey) < ($1.start, $1.occurrenceKey) }
    }

    /// How long a reminder stays due after its time: a Mac woken a little
    /// late still gets it.
    public static let reminderWindow: TimeInterval = 5 * 60

    /// Pop-up reminders set in Google Calendar (`CalendarEvent.reminders`)
    /// due at `now`, all-day events included: an event and its reminder's
    /// key in `skip`. A reminder at the same time as the peek before a
    /// meeting or at its start, within a minute, is left to that peek.
    public static func dueReminders(
        _ events: [CalendarEvent],
        now: Date,
        policy: AlertPolicy,
        skip: Set<String>
    ) -> [(event: CalendarEvent, key: String)] {
        var result: [(CalendarEvent, String, Date)] = []
        for e in events where e.selfResponse != .declined && now < max(e.end, e.start.addingTimeInterval(60)) {
            for minutes in e.reminders {
                let at = e.start.addingTimeInterval(-TimeInterval(minutes * 60))
                let key = reminderKey(e, minutes: minutes)
                guard now >= at, now < at.addingTimeInterval(reminderWindow), !skip.contains(key) else { continue }
                if !e.isWholeDay {
                    let peeks = [e.start.addingTimeInterval(-policy.leadTime), e.start]
                    if peeks.contains(where: { abs($0.timeIntervalSince(at)) < 60 }) { continue }
                }
                result.append((e, key, at))
            }
        }
        return result.sorted { ($0.2, $0.1) < ($1.2, $1.1) }.map { ($0.0, $0.1) }
    }

    public static func reminderKey(_ e: CalendarEvent, minutes: Int) -> String {
        "\(e.occurrenceKey)#\(minutes)"
    }

    /// End of the alert window, as in `AlertPlanner.due`: the notification
    /// is withdrawn then, and its key can be forgotten.
    public static func windowEnd(_ e: CalendarEvent, policy: AlertPolicy) -> Date {
        min(e.start.addingTimeInterval(policy.lingerAfterStart), e.end)
    }

}
