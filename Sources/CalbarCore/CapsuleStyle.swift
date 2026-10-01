import Foundation

/// Fill of the merged menu bar capsule while the Join queue has a primary
/// meeting.
public enum CapsuleStyle: Equatable, Sendable {
    /// Fallback when the badge does not say how close the meeting is.
    case accent
    /// Within the alert lead time: orange.
    case soon
    /// One minute or less before the start, or started: red.
    case urgent

    /// Nil when no meeting with a link is due: the icon is the plain glyph.
    /// The color follows the badge, so the capsule and the glyph it
    /// replaces always agree. A warning badge hides the urgency, so the
    /// primary meeting's own timing decides then.
    public static func make(badge: MenuBarBadge, primary: CalendarEvent?, now: Date) -> CapsuleStyle? {
        guard let primary else { return nil }
        switch badge {
        case .countdown(_, .soon): return .soon
        case .countdown(_, .imminent), .live: return .urgent
        case .countdown(_, .normal), .inMeeting: return .accent
        case .warning, .none:
            let left = primary.start.timeIntervalSince(now)
            return left <= MenuBarBadge.imminentThreshold ? .urgent : .soon
        }
    }
}
