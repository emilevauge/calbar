import Foundation

/// An out of office event: Google declines the meetings it overlaps, as
/// the user chose.
public struct OutOfOffice: Codable, Equatable, Hashable, Sendable {
    /// Which meetings during the absence Google declines.
    public enum Decline: String, Codable, CaseIterable, Sendable {
        case none = "declineNone"
        /// Invitations received after the absence is set.
        case newOnly = "declineOnlyNewConflictingInvitations"
        /// Those, and the meetings already in the calendar.
        case all = "declineAllConflictingInvitations"

        public var label: String {
            switch self {
            case .none: "Don't decline meetings"
            case .newOnly: "Decline new invitations"
            case .all: "Decline new and existing meetings"
            }
        }
    }

    public var decline: Decline
    /// Sent with each declined invitation.
    public var message: String

    public static let defaultMessage = "Declined because I am out of office"

    public init(decline: Decline = .newOnly, message: String = OutOfOffice.defaultMessage) {
        self.decline = decline
        self.message = message
    }

    /// `outOfOfficeProperties` of an event.
    public var properties: [String: Any] {
        var json: [String: Any] = ["autoDeclineMode": decline.rawValue]
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if decline != .none, !text.isEmpty { json["declineMessage"] = text }
        return json
    }
}
