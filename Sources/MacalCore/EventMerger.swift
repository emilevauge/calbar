import Foundation

/// Combines the events of every account and calendar into one list.
public enum EventMerger {
    public static func merge(_ events: [CalendarEvent], showDeclined: Bool) -> [CalendarEvent] {
        var best: [String: CalendarEvent] = [:]
        for event in events {
            let key = event.occurrenceKey
            if let current = best[key], !isBetter(event, than: current) { continue }
            best[key] = event
        }
        return best.values
            .filter { showDeclined || $0.selfResponse != .declined }
            .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }

    /// Higher score wins; on a tie the smaller id, so the result does not
    /// depend on the order the accounts answered in.
    private static func isBetter(_ a: CalendarEvent, than b: CalendarEvent) -> Bool {
        let (sa, sb) = (score(a), score(b))
        return sa != sb ? sa > sb : a.id < b.id
    }

    /// Which copy of a duplicated meeting to keep.
    ///
    /// `selfResponse` comes from the attendee Google flags with
    /// `self: true`, and Google sets that flag for the owner of the
    /// calendar the copy was read from, not for the signed-in user. A copy
    /// read from a colleague's shared calendar therefore carries the
    /// colleague's answer. Only the copy on the account's primary calendar
    /// (whose id is the account email) reliably holds the user's own
    /// answer, so it outranks everything else: primary calendar +4, not
    /// declined +2, video link +1.
    private static func score(_ e: CalendarEvent) -> Int {
        (e.calendarID == e.accountEmail ? 4 : 0)
            + (e.selfResponse != .declined ? 2 : 0)
            + (e.meeting != nil ? 1 : 0)
    }
}
