import Foundation

/// The time at home, for a trip in another time zone.
public enum HomeClock {
    /// The home zone when its time differs from `current` at `date`,
    /// else nil: at home, or in a zone with the same time.
    public static func away(home: String, current: TimeZone, at date: Date) -> TimeZone? {
        guard let zone = TimeZone(identifier: home),
              zone.secondsFromGMT(for: date) != current.secondsFromGMT(for: date) else { return nil }
        return zone
    }

    /// "15:00", or "15:30" in a zone off by half an hour.
    public static func label(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "Paris (GMT+1)", for the settings.
    public static func name(_ zone: TimeZone, at date: Date) -> String {
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? zone.identifier
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        let offset = seconds == 0 ? "" : minutes == 0 ? "\(sign)\(hours)" : String(format: "%@%d:%02d", sign, hours, minutes)
        return "\(city) (GMT\(offset))"
    }

    /// "CET", "EST": `abbreviation(for:)` gives "GMT+1" for Paris in
    /// most locales, so a "GMT" answer is looked up in macOS's table,
    /// among the zones of the same region with the same time.
    public static func abbreviation(_ zone: TimeZone, at date: Date) -> String {
        let given = zone.abbreviation(for: date) ?? zone.identifier
        guard given.hasPrefix("GMT"), given != "GMT" else { return given }
        let region = zone.identifier.split(separator: "/").first
        let dst = zone.isDaylightSavingTime(for: date)
        let matches = TimeZone.abbreviationDictionary.filter { _, identifier in
            guard let other = TimeZone(identifier: identifier) else { return false }
            return identifier.split(separator: "/").first == region
                && other.secondsFromGMT(for: date) == zone.secondsFromGMT(for: date)
                && other.isDaylightSavingTime(for: date) == dst
        }.keys
        // Both CET and CEST name Paris: summer time is the longer one.
        let pick = dst ? matches.max { ($0.count, $0) < ($1.count, $1) } : matches.min { ($0.count, $0) < ($1.count, $1) }
        return pick ?? given
    }
}
