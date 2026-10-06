import Foundation

public struct AlertPolicy: Equatable, Sendable {
    /// How long before the start the Join button shows.
    public let leadTime: TimeInterval
    /// How long after the start the button stays if nobody touched it.
    public let lingerAfterStart: TimeInterval

    public init(leadTime: TimeInterval, lingerAfterStart: TimeInterval) {
        self.leadTime = leadTime
        self.lingerAfterStart = lingerAfterStart
    }
}

public enum AlertPlanner {
    /// Events whose alert should be on screen at `now`.
    /// `dismissed` holds the `occurrenceKey` of alerts already handled.
    public static func due(
        _ events: [CalendarEvent],
        now: Date,
        policy: AlertPolicy,
        dismissed: Set<String>
    ) -> [CalendarEvent] {
        events.filter { e in
            !e.isWholeDay
                && e.selfResponse != .declined
                && !dismissed.contains(e.occurrenceKey)
                && now >= e.start.addingTimeInterval(-policy.leadTime)
                && now < e.start.addingTimeInterval(policy.lingerAfterStart)
                && now < e.end
        }
    }
}
