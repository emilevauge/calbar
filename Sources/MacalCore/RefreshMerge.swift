import Foundation

/// One calendar as seen from one account. The same shared calendar has
/// the same ID in every account, so the email is part of the key.
public struct CalendarKey: Hashable, Sendable {
    public let email: String
    public let calendarID: String

    public init(email: String, calendarID: String) {
        self.email = email
        self.calendarID = calendarID
    }
}

/// Combines a refresh pass with the previous events, so a failure on one
/// account or one calendar does not wipe what was shown before.
public enum RefreshMerge {
    /// Previous events that the refresh could not replace: every event of
    /// a failed account, and the events of each failed calendar.
    public static func kept(
        previous: [CalendarEvent],
        failedAccounts: Set<String>,
        failedCalendars: Set<CalendarKey>
    ) -> [CalendarEvent] {
        previous.filter { event in
            failedAccounts.contains(event.accountEmail)
                || failedCalendars.contains(CalendarKey(email: event.accountEmail, calendarID: event.calendarID))
        }
    }

    public static func merge(
        collected: [CalendarEvent],
        previous: [CalendarEvent],
        failedAccounts: Set<String>,
        failedCalendars: Set<CalendarKey>
    ) -> [CalendarEvent] {
        collected + kept(previous: previous, failedAccounts: failedAccounts, failedCalendars: failedCalendars)
    }
}
