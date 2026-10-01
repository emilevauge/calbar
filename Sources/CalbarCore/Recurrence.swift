import Foundation

/// Which occurrences of a recurring event a change or a deletion applies
/// to, as in Google Calendar.
public enum RecurrenceScope: String, CaseIterable, Sendable {
    case this, following, all

    public var label: String {
        switch self {
        case .this: return "This event"
        case .following: return "This and following events"
        case .all: return "All events"
        }
    }
}

/// How a new event repeats, the choices Google Calendar offers for its
/// start day.
public enum RepeatRule: String, CaseIterable, Sendable {
    case none, daily, weekdays, weekly, biweekly, monthlyByWeekday, monthlyByDay, yearly

    private static let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                     "August", "September", "October", "November", "December"]
    private static let ordinals = ["first", "second", "third", "fourth"]

    /// The `RRULE:` line for an event starting `start`, nil for `.none`.
    public func rrule(start: Date, calendar: Calendar = .current) -> String? {
        let weekday = calendar.component(.weekday, from: start)
        let code = Self.codes[weekday - 1]
        switch self {
        case .none: return nil
        case .daily: return "RRULE:FREQ=DAILY"
        case .weekdays: return "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly: return "RRULE:FREQ=WEEKLY;BYDAY=\(code)"
        case .biweekly: return "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=\(code)"
        case .monthlyByWeekday: return "RRULE:FREQ=MONTHLY;BYDAY=\(Self.weekOfMonth(start, calendar: calendar))\(code)"
        case .monthlyByDay: return "RRULE:FREQ=MONTHLY;BYMONTHDAY=\(calendar.component(.day, from: start))"
        case .yearly: return "RRULE:FREQ=YEARLY"
        }
    }

    /// "Weekly on Tuesday", "Monthly on the last Friday" for `start`.
    public func label(start: Date, calendar: Calendar = .current) -> String {
        let day = Self.dayNames[calendar.component(.weekday, from: start) - 1]
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Daily"
        case .weekdays: return "Every weekday (Monday to Friday)"
        case .weekly: return "Weekly on \(day)"
        case .biweekly: return "Every 2 weeks on \(day)"
        case .monthlyByWeekday:
            let n = Self.weekOfMonth(start, calendar: calendar)
            return "Monthly on the \(n == -1 ? "last" : Self.ordinals[n - 1]) \(day)"
        case .monthlyByDay: return "Monthly on day \(calendar.component(.day, from: start))"
        case .yearly:
            let month = Self.monthNames[calendar.component(.month, from: start) - 1]
            return "Annually on \(month) \(calendar.component(.day, from: start))"
        }
    }

    /// 1 to 4 for the first to fourth such weekday of the month, -1 for a
    /// fifth one, which some months lack: "the last".
    static func weekOfMonth(_ date: Date, calendar: Calendar) -> Int {
        let n = (calendar.component(.day, from: date) - 1) / 7 + 1
        return n >= 5 ? -1 : n
    }
}

public enum Recurrence {
    /// The series' rules ended just before the occurrence at `cut`, for
    /// "delete this and following": `UNTIL` replaces any `COUNT` or
    /// `UNTIL`, as a UTC time, or a day for an all-day series. Other
    /// lines (`EXDATE`, `RDATE`) stay.
    public static func truncate(_ rules: [String], before cut: Date, allDay: Bool,
                                calendar: Calendar = .current) -> [String] {
        let until = allDay ? day(cut.addingTimeInterval(-86_400), calendar: calendar) : utc(cut.addingTimeInterval(-1))
        return rules.map { line in
            guard line.uppercased().hasPrefix("RRULE:") else { return line }
            let parts = line.dropFirst("RRULE:".count).split(separator: ";").filter {
                let key = $0.split(separator: "=").first?.uppercased()
                return key != "COUNT" && key != "UNTIL"
            }
            return "RRULE:" + (parts + ["UNTIL=\(until)"]).joined(separator: ";")
        }
    }

    private static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
