import AppKit
import MacalCore

/// Opens the popover in peek mode on a meeting, for a few seconds, when
/// it enters its alert window and again when it starts, instead of a
/// system notification. Once per occurrence and stage, like
/// `NotificationPlanner` decides.
///
/// A stage is marked done only once the peek showed: while the screen is
/// locked or the full popover is open, it waits, and shows on a later tick
/// if its window is still open. A peek the user is already looking at
/// moves to the newer meeting.
@MainActor
final class MeetingPeeker {
    /// How long a peek stays without the pointer on it.
    static let duration: TimeInterval = 8

    private let store: EventStore
    private let join: JoinController
    /// Shows the peek on an event for `duration`; false when it could not.
    var show: (CalendarEvent) -> Bool = { _ in false }

    /// `occurrenceKey` of the occurrences peeked before the start, and at
    /// the start, with the end of their alert window. In memory only.
    private var shownSoon: [String: Date] = [:]
    private var shownAtStart: [String: Date] = [:]

    init(store: EventStore, join: JoinController) {
        self.store = store
        self.join = join
    }

    /// Called on every tick and data change.
    func update(now: Date) {
        shownSoon = shownSoon.filter { $0.value > now }
        shownAtStart = shownAtStart.filter { $0.value > now }
        guard Prefs.notifyBeforeMeetings, !Session.isScreenLocked else { return }
        let policy = Prefs.alertPolicy
        let dismissed = join.dismissed
        // The start of a meeting comes first: it is the more urgent.
        if let event = NotificationPlanner.dueAtStart(store.events, now: now, policy: policy,
                                                      skip: Set(shownAtStart.keys).union(dismissed)).first {
            if show(event) {
                let end = NotificationPlanner.windowEnd(event, policy: policy)
                shownAtStart[event.occurrenceKey] = end
                shownSoon[event.occurrenceKey] = end
            }
            return
        }
        let skip = Set(shownSoon.keys).union(shownAtStart.keys).union(dismissed)
        if let event = NotificationPlanner.due(store.events, now: now, policy: policy, skip: skip).first,
           show(event) {
            shownSoon[event.occurrenceKey] = NotificationPlanner.windowEnd(event, policy: policy)
        }
    }
}

enum Session {
    /// A locked screen hides the popover: whatever wants to show it waits.
    static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
