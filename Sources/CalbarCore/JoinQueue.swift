import Foundation

/// Meetings offered by the Join button in the menu bar: the due
/// alerts that have a video link, earliest first.
public struct JoinQueue: Equatable, Sendable {
    public let meetings: [CalendarEvent]

    public init(
        events: [CalendarEvent],
        now: Date,
        policy: AlertPolicy,
        dismissed: Set<String>
    ) {
        meetings = AlertPlanner.due(events, now: now, policy: policy, dismissed: dismissed)
            .filter { $0.meeting != nil }
            .sorted { ($0.start, $0.occurrenceKey) < ($1.start, $1.occurrenceKey) }
    }

    /// The meeting the button shows and joins on click.
    public var primary: CalendarEvent? { meetings.first }

    /// Due meetings besides the primary one.
    public var extraCount: Int { max(0, meetings.count - 1) }

    /// "+1", "+2", or nil when only one meeting is due.
    public var extraLabel: String? { extraCount > 0 ? "+\(extraCount)" : nil }
}
