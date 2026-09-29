import Foundation

/// What the menu bar icon shows inside its calendar glyph. It never shows
/// the date: only the time left before the next meeting of the day, in red
/// during the first minutes of a meeting.
public enum MenuBarBadge: Equatable, Sendable {
    /// How close the next meeting is, from the time left before its start.
    public enum Urgency: Equatable, Sendable {
        /// Outside the alert lead time: outline glyph.
        case normal
        /// Within the alert lead time, when the Join button shows: orange.
        case soon
        /// One minute or less before the start: red.
        case imminent
    }

    /// Time left at or under which a meeting is imminent.
    public static let imminentThreshold: TimeInterval = 60

    /// An account must be reconnected: "!", filled glyph.
    case warning
    /// A meeting started less than `lingerAfterStart` ago and was not
    /// dismissed ("Dismiss"; joining does not count): red calendar page with
    /// the usual countdown to the next meeting, empty when none is left
    /// today. `hasLink` tells whether the started meeting has a video link.
    case live(hasLink: Bool, nextMinutes: Int?)
    /// Minutes before the next timed meeting of today, rounded up, with how
    /// close it is.
    case countdown(minutes: Int, urgency: Urgency)
    /// No timed meeting left today: empty outline glyph.
    case none

    /// "25" under an hour, then whole hours rounded down: "1h", "2h".
    public var text: String {
        switch self {
        case .warning: return "!"
        case .countdown(let m, _), .live(_, let m?): return Self.format(m)
        case .live(_, nil), .none: return ""
        }
    }

    private static func format(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)" : "\(minutes / 60)h"
    }

    /// Urgency of a countdown, nil for `.warning`, `.live` and `.none`.
    public var urgency: Urgency? {
        if case .countdown(_, let urgency) = self { return urgency }
        return nil
    }

    /// Filled glyph: a warning, a started meeting to join, or a meeting
    /// within the lead time.
    public var isProminent: Bool {
        switch self {
        case .warning, .live: return true
        case .countdown(_, let urgency): return urgency != .normal
        case .none: return false
        }
    }

    /// Counts down to `NextMeeting.find`. `due` holds the current alerts
    /// (`AlertPlanner.due`, dismissed ones left out): when one of them has
    /// started, the badge is `.live` instead of the countdown.
    public static func compute(
        events: [CalendarEvent],
        now: Date,
        leadTime: TimeInterval,
        calendar: Calendar,
        needsAttention: Bool,
        due: [CalendarEvent] = []
    ) -> MenuBarBadge {
        if needsAttention { return .warning }
        let next = NextMeeting.find(events: events, now: now, calendar: calendar)
        let started = due.filter { $0.start <= now }
        if !started.isEmpty {
            return .live(
                hasLink: started.contains { $0.meeting != nil },
                nextMinutes: next.map { minutesLeft(until: $0.start, now: now) }
            )
        }
        guard let next else { return .none }
        let left = next.start.timeIntervalSince(now)
        // Same rule as AlertPlanner: the Join button shows at start - leadTime.
        let urgency: Urgency
        if left <= imminentThreshold {
            urgency = .imminent
        } else if left <= leadTime {
            urgency = .soon
        } else {
            urgency = .normal
        }
        return .countdown(minutes: minutesLeft(until: next.start, now: now), urgency: urgency)
    }

    private static func minutesLeft(until start: Date, now: Date) -> Int {
        Int((start.timeIntervalSince(now) / 60).rounded(.up))
    }
}
