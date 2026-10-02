import Foundation
import CalbarCore

/// UserDefaults keys and defaults. Views bind the same keys with
/// `@AppStorage` and must use the same default values.
enum Prefs {
    static let leadMinutesKey = "alertLeadMinutes"
    static let lingerMinutesKey = "alertLingerMinutes"
    static let showDeclinedKey = "showDeclined"
    static let notifyBeforeMeetingsKey = "notifyBeforeMeetings"
    static let soundBeforeMeetingsKey = "soundBeforeMeetings"
    static let openPanelAtDayStartKey = "openPanelAtDayStart"
    /// First and last hour the week view shows without scrolling.
    static let weekStartHourKey = "weekStartHour"
    static let weekEndHourKey = "weekEndHour"
    /// "day" or "week".
    static let viewModeKey = "viewMode"
    /// Weekdays the week view shows, `Calendar` numbers (1 = Sunday):
    /// "1234567" for all, "23456" for Monday to Friday.
    static let weekDaysKey = "weekDays"
    /// "yyyy-MM-dd" of the last day the popover opened by itself.
    static let lastDayStartOpenKey = "lastDayStartOpen"

    static func register() {
        UserDefaults.standard.register(defaults: [
            leadMinutesKey: 10,
            lingerMinutesKey: 5,
            showDeclinedKey: false,
            notifyBeforeMeetingsKey: true,
            soundBeforeMeetingsKey: true,
            openPanelAtDayStartKey: true,
            weekStartHourKey: 9,
            weekEndHourKey: 19,
            viewModeKey: "day",
            weekDaysKey: "1234567",
        ])
    }

    static var showDeclined: Bool {
        UserDefaults.standard.bool(forKey: showDeclinedKey)
    }

    static var notifyBeforeMeetings: Bool {
        UserDefaults.standard.bool(forKey: notifyBeforeMeetingsKey)
    }

    /// A sound when the panel opens by itself before a meeting.
    static var soundBeforeMeetings: Bool {
        UserDefaults.standard.bool(forKey: soundBeforeMeetingsKey)
    }

    static var openPanelAtDayStart: Bool {
        UserDefaults.standard.bool(forKey: openPanelAtDayStartKey)
    }

    static var lastDayStartOpen: String? {
        get { UserDefaults.standard.string(forKey: lastDayStartOpenKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastDayStartOpenKey) }
    }

    static var alertPolicy: AlertPolicy {
        let d = UserDefaults.standard
        return AlertPolicy(
            leadTime: TimeInterval(d.integer(forKey: leadMinutesKey) * 60),
            lingerAfterStart: TimeInterval(d.integer(forKey: lingerMinutesKey) * 60)
        )
    }
}
