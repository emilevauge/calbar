import Foundation

/// Calendar day boundaries, in the local time zone of `calendar`.
public enum DayWindow {
    /// From the start of the day holding `date` to the start of the day
    /// `days` later. 23 or 25 hours long across a daylight saving change.
    public static func interval(for date: Date, days: Int = 1, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        return DateInterval(start: start, end: end)
    }

    /// Start of the day `offset` days after the day holding `date`.
    public static func day(offset: Int, from date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    }

    /// Whether `event` belongs to `window`. A zero-length event at the
    /// window start has `end == start` and still belongs to it; an event
    /// ending exactly at the start does not.
    public static func contains(_ event: CalendarEvent, in window: DateInterval) -> Bool {
        event.start < window.end && (event.end > window.start || event.start >= window.start)
    }

    /// "Yesterday", "Today", "Tomorrow", `nil` for other days.
    public static func relativeName(offset: Int) -> String? {
        switch offset {
        case -1: "Yesterday"
        case 0: "Today"
        case 1: "Tomorrow"
        default: nil
        }
    }
}

/// What the popover shows for a day other than today: every event of the
/// day, without splitting past and upcoming ones.
public struct DayListing: Equatable, Sendable {
    public let allDay: [CalendarEvent]
    /// Timed events in start order, including those that start the day
    /// before or end the day after.
    public let timed: [CalendarEvent]

    public var count: Int { allDay.count + timed.count }
    public var isEmpty: Bool { count == 0 }

    public static func build(events: [CalendarEvent], day: Date, calendar: Calendar) -> DayListing {
        let window = DayWindow.interval(for: day, calendar: calendar)
        let events = events.filter { DayWindow.contains($0, in: window) }.sorted { $0.start < $1.start }
        return DayListing(allDay: events.filter(\.isAllDay), timed: events.filter { !$0.isAllDay })
    }
}

/// State of a day fetched on demand.
public enum DayContent: Equatable, Sendable {
    case loading
    case failed
    case loaded(DayListing)
}

/// In-memory cache of values fetched per day, keyed by the start of the day.
/// An entry is fresh for `maxAge`, or until `invalidate()`; a stale entry
/// keeps its value on screen while it is fetched again.
public struct DayCache<Value> {
    public static var maxAge: TimeInterval { 300 }

    public struct Entry {
        public fileprivate(set) var value: Value?
        public fileprivate(set) var isLoading = false
        /// The last fetch failed. Not retried automatically until the
        /// next invalidation, so a failing day does not loop.
        public fileprivate(set) var failed = false
        /// `nil` once invalidated.
        fileprivate var fetchedAt: Date?
        /// Generation the running fetch started in.
        fileprivate var generation = 0
    }

    private var entries: [Date: Entry] = [:]
    private var generation = 0

    public init() {}

    public func entry(for day: Date) -> Entry? {
        entries[day]
    }

    /// Every value held, in no order.
    public var values: [Value] { entries.values.compactMap(\.value) }

    public func needsFetch(_ day: Date, now: Date) -> Bool {
        guard let entry = entries[day] else { return true }
        if entry.isLoading || entry.failed && entry.generation == generation { return false }
        guard let fetchedAt = entry.fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= Self.maxAge
    }

    public mutating func begin(_ day: Date) {
        var entry = entries[day] ?? Entry()
        entry.isLoading = true
        entry.failed = false
        entry.generation = generation
        entries[day] = entry
    }

    /// A result from a fetch started before the last invalidation is shown
    /// but stays stale.
    public mutating func finish(_ day: Date, value: Value, at date: Date) {
        var entry = entries[day] ?? Entry()
        entry.value = value
        entry.isLoading = false
        entry.failed = false
        entry.fetchedAt = entry.generation == generation ? date : nil
        entries[day] = entry
    }

    public mutating func fail(_ day: Date) {
        var entry = entries[day] ?? Entry()
        entry.isLoading = false
        entry.failed = true
        entries[day] = entry
    }

    /// Marks every entry stale. Values stay until their day is fetched again.
    public mutating func invalidate() {
        generation += 1
        for day in entries.keys {
            entries[day]?.fetchedAt = nil
        }
    }

    /// Edits every cached value in place, for instance to drop a removed account.
    public mutating func modifyValues(_ change: (inout Value) -> Void) {
        for day in entries.keys {
            if var value = entries[day]?.value {
                change(&value)
                entries[day]?.value = value
            }
        }
    }
}

extension DayCache.Entry: Equatable where Value: Equatable {}
extension DayCache: Sendable where Value: Sendable {}
extension DayCache.Entry: Sendable where Value: Sendable {}
