import Foundation

public enum ResponseStatus: String, Codable, Sendable {
    case accepted, declined, tentative, needsAction

    init(google: String?) {
        self = ResponseStatus(rawValue: google ?? "") ?? .needsAction
    }
}

public struct Person: Equatable, Codable, Sendable {
    public let email: String
    public let name: String?

    public init(email: String, name: String?) {
        self.email = email
        self.name = name
    }

    public var displayName: String { name ?? email }
}

public struct Attendee: Equatable, Codable, Sendable {
    public let person: Person
    public let response: ResponseStatus
    public let isOrganizer: Bool
    public let isSelf: Bool
    public let isOptional: Bool

    public init(person: Person, response: ResponseStatus, isOrganizer: Bool, isSelf: Bool, isOptional: Bool) {
        self.person = person
        self.response = response
        self.isOrganizer = isOrganizer
        self.isSelf = isSelf
        self.isOptional = isOptional
    }
}

public struct Attachment: Equatable, Codable, Sendable {
    public let title: String
    public let url: URL
    public let mimeType: String?
    public let iconURL: URL?

    public init(title: String, url: URL, mimeType: String?, iconURL: URL?) {
        self.title = title
        self.url = url
        self.mimeType = mimeType
        self.iconURL = iconURL
    }
}

/// One occurrence of a calendar event, as seen from one account.
public struct CalendarEvent: Identifiable, Equatable, Codable, Sendable {
    /// Unique across accounts: "<account>/<calendar>/<google event id>".
    public let id: String
    /// Shared by every copy of the same meeting, across accounts, and by
    /// every occurrence of a recurring meeting.
    public let iCalUID: String
    public let accountEmail: String
    public let calendarID: String
    public let colorHex: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    /// Raw Google description, often HTML.
    public let notes: String?
    public let htmlLink: URL?
    public let organizer: Person?
    public let attendees: [Attendee]
    public let attachments: [Attachment]
    public let meeting: MeetingLink?
    /// The account owner's answer. `.accepted` when they organize the
    /// event or when it has no attendee list.
    public let selfResponse: ResponseStatus

    public init(
        id: String, iCalUID: String, accountEmail: String, calendarID: String,
        colorHex: String, title: String, start: Date, end: Date, isAllDay: Bool,
        location: String?, notes: String?, htmlLink: URL?, organizer: Person?,
        attendees: [Attendee], attachments: [Attachment], meeting: MeetingLink?,
        selfResponse: ResponseStatus
    ) {
        self.id = id
        self.iCalUID = iCalUID
        self.accountEmail = accountEmail
        self.calendarID = calendarID
        self.colorHex = colorHex
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.htmlLink = htmlLink
        self.organizer = organizer
        self.attendees = attendees
        self.attachments = attachments
        self.meeting = meeting
        self.selfResponse = selfResponse
    }

    /// Identifies one occurrence at one time slot. Used to deduplicate
    /// across accounts and to remember dismissed alerts: a meeting moved to
    /// another time gets a new key and alerts again.
    public var occurrenceKey: String {
        "\(iCalUID)@\(Int(start.timeIntervalSince1970))"
    }

    /// `htmlLink` pinned to the right Google account, otherwise the browser
    /// opens it in whichever account is signed in first.
    public var webURL: URL? {
        guard let htmlLink,
              var c = URLComponents(url: htmlLink, resolvingAgainstBaseURL: false) else { return nil }
        c.percentEncodedQueryItems = (c.percentEncodedQueryItems ?? []) + [GoogleCalendarWeb.authuserItem(accountEmail)]
        return c.url
    }
}

/// A calendar of one account, with the user's on/off choice.
public struct CalendarInfo: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let colorHex: String
    public let isPrimary: Bool
    public var enabled: Bool

    public init(id: String, name: String, colorHex: String, isPrimary: Bool, enabled: Bool) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isPrimary = isPrimary
        self.enabled = enabled
    }
}

public struct Account: Identifiable, Equatable, Codable, Sendable {
    public var id: String { email }
    public let email: String
    public var calendars: [CalendarInfo]
    /// The refresh token was revoked or expired: the user must sign in again.
    public var needsReconnect: Bool

    public init(email: String, calendars: [CalendarInfo], needsReconnect: Bool) {
        self.email = email
        self.calendars = calendars
        self.needsReconnect = needsReconnect
    }
}
