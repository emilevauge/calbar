import Foundation

/// Decides whether the popover opens by itself at the first user activity
/// of a day (launch, wake, unlock): at most once per calendar day, and only
/// while a meeting is left today.
public enum DayStartPolicy {
    /// "yyyy-MM-dd" of `date` in `calendar`, used to remember the last day
    /// the popover opened by itself. Built from calendar components, so it
    /// follows the calendar's time zone and daylight saving changes.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Timed meetings of today not finished yet and not declined.
    public static func remainingMeetings(in agenda: DayAgenda) -> Int {
        agenda.current.filter { $0.selfResponse != .declined }.count
    }

    public static func shouldOpen(
        lastOpenedDay: String?, now: Date, calendar: Calendar,
        remainingMeetings: Int, enabled: Bool
    ) -> Bool {
        guard enabled, remainingMeetings > 0 else { return false }
        return lastOpenedDay != dayKey(for: now, calendar: calendar)
    }
}
