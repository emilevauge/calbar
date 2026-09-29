import Foundation
import MacalCore

/// UserDefaults keys and defaults. Views bind the same keys with
/// `@AppStorage` and must use the same default values.
enum Prefs {
    static let leadMinutesKey = "alertLeadMinutes"
    static let lingerMinutesKey = "alertLingerMinutes"
    static let showDeclinedKey = "showDeclined"
    static let notifyBeforeMeetingsKey = "notifyBeforeMeetings"
    static let openPanelAtDayStartKey = "openPanelAtDayStart"
    /// "yyyy-MM-dd" of the last day the popover opened by itself.
    static let lastDayStartOpenKey = "lastDayStartOpen"

    static func register() {
        UserDefaults.standard.register(defaults: [
            leadMinutesKey: 10,
            lingerMinutesKey: 5,
            showDeclinedKey: false,
            notifyBeforeMeetingsKey: true,
            openPanelAtDayStartKey: true,
        ])
    }

    static var showDeclined: Bool {
        UserDefaults.standard.bool(forKey: showDeclinedKey)
    }

    static var notifyBeforeMeetings: Bool {
        UserDefaults.standard.bool(forKey: notifyBeforeMeetingsKey)
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
