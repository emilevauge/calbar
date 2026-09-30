import Foundation

/// What the menu bar icon shows inside its calendar glyph. It never shows
/// the date: the time left before the next meeting of the day, or during a
/// meeting the time left in it, with the page filling up as it runs. Red
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

    /// The meeting running now: minutes left, rounded up, and the elapsed
    /// part of it, from 0 to 1.
    public struct Progress: Equatable, Sendable {
        public let minutesLeft: Int
        public let fraction: Double

        public init(minutesLeft: Int, fraction: Double) {
            self.minutesLeft = minutesLeft
            self.fraction = fraction
        }

        public static func of(_ event: CalendarEvent, now: Date) -> Progress {
            let total = event.end.timeIntervalSince(event.start)
            let done = total > 0 ? now.timeIntervalSince(event.start) / total : 1
            return Progress(minutesLeft: MenuBarBadge.minutesLeft(until: event.end, now: now),
                            fraction: min(max(done, 0), 1))
        }
    }

    /// Time left at or under which a meeting is imminent.
    public static let imminentThreshold: TimeInterval = 60

    /// An account must be reconnected: "!", filled glyph.
    case warning
    /// A meeting started less than `lingerAfterStart` ago and was not
    /// dismissed ("Dismiss"; joining does not count): red calendar page
    /// filling up with the meeting, and its minutes left; empty for a
    /// zero-length event. `hasLink` tells whether the started meeting has a
    /// video link.
    case live(hasLink: Bool, meeting: Progress?)
    /// In a meeting past its first minutes: outline page filling up, and
    /// the minutes left in it.
    case inMeeting(Progress)
    /// Minutes before the next timed meeting of today, rounded up, with how
    /// close it is.
    case countdown(minutes: Int, urgency: Urgency)
    /// No timed meeting left today: empty outline glyph.
    case none

    /// "25" under an hour, then whole hours rounded down: "1h", "2h".
    public var text: String {
        switch self {
        case .warning: return "!"
        case .countdown(let m, _): return Self.format(m)
        case .live(_, let p?), .inMeeting(let p): return Self.format(p.minutesLeft)
        case .live(_, nil), .none: return ""
        }
    }

    private static func format(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)" : "\(minutes / 60)h"
    }

    /// Elapsed part of the meeting running now, nil outside a meeting.
    public var progress: Double? {
        switch self {
        case .live(_, let p?), .inMeeting(let p): return p.fraction
        default: return nil
        }
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
        case .inMeeting, .none: return false
        }
    }

    /// Counts down to `NextMeeting.find`. `due` holds the current alerts
    /// (`AlertPlanner.due`, dismissed ones left out): when one of them has
    /// started, the badge is `.live`. Otherwise, during a meeting
    /// (`NextMeeting.ongoing`), `.inMeeting`, unless the next meeting is
    /// within the lead time: its orange or red countdown comes first.
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
        let current = NextMeeting.ongoing(events: events, now: now)
        let started = due.filter { $0.start <= now }
        if !started.isEmpty {
            return .live(
                hasLink: started.contains { $0.meeting != nil },
                meeting: current.map { Progress.of($0, now: now) }
            )
        }
        if let current, next.map({ $0.start.timeIntervalSince(now) > leadTime }) ?? true {
            return .inMeeting(Progress.of(current, now: now))
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

    static func minutesLeft(until start: Date, now: Date) -> Int {
        Int((start.timeIntervalSince(now) / 60).rounded(.up))
    }
}
