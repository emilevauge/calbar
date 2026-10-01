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
    /// The event id in Google's API, needed to answer the invitation. For
    /// an occurrence of a recurring event, the id of that occurrence.
    public let googleEventID: String
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
        selfResponse: ResponseStatus, googleEventID: String? = nil
    ) {
        self.id = id
        self.googleEventID = googleEventID ?? Self.googleID(fromCompositeID: id)
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

    private enum CodingKeys: String, CodingKey {
        case id, googleEventID, iCalUID, accountEmail, calendarID, colorHex, title, start, end, isAllDay
        case location, notes, htmlLink, organizer, attendees, attachments, meeting, selfResponse
    }

    /// Events cached before `googleEventID` existed take it from the end
    /// of the composite `id`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        self.init(
            id: id,
            iCalUID: try c.decode(String.self, forKey: .iCalUID),
            accountEmail: try c.decode(String.self, forKey: .accountEmail),
            calendarID: try c.decode(String.self, forKey: .calendarID),
            colorHex: try c.decode(String.self, forKey: .colorHex),
            title: try c.decode(String.self, forKey: .title),
            start: try c.decode(Date.self, forKey: .start),
            end: try c.decode(Date.self, forKey: .end),
            isAllDay: try c.decode(Bool.self, forKey: .isAllDay),
            location: try c.decodeIfPresent(String.self, forKey: .location),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            htmlLink: try c.decodeIfPresent(URL.self, forKey: .htmlLink),
            organizer: try c.decodeIfPresent(Person.self, forKey: .organizer),
            attendees: try c.decode([Attendee].self, forKey: .attendees),
            attachments: try c.decode([Attachment].self, forKey: .attachments),
            meeting: try c.decodeIfPresent(MeetingLink.self, forKey: .meeting),
            selfResponse: try c.decode(ResponseStatus.self, forKey: .selfResponse),
            googleEventID: try c.decodeIfPresent(String.self, forKey: .googleEventID)
        )
    }

    /// "<account>/<calendar>/<google event id>" to its last part. Google
    /// event ids never contain a slash.
    static func googleID(fromCompositeID id: String) -> String {
        id.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? id
    }

    /// The user is invited by someone else and can answer yes, maybe or no.
    ///
    /// Only on the account's primary calendar: Google flags as `self` the
    /// owner of the calendar a copy was read from, so on a colleague's
    /// shared calendar an answer would change the colleague's answer.
    public var canRespond: Bool {
        calendarID == accountEmail && attendees.contains { $0.isSelf && !$0.isOrganizer }
    }

    /// The user may delete it: on one of their own calendars (`own`
    /// emails), organized by them, or without guests. Deleting someone
    /// else's invitation is declining, not this.
    public func isDeletable(own: Set<String>) -> Bool {
        guard own.contains(calendarID.lowercased()) || own.contains(accountEmail.lowercased()) else { return false }
        if attendees.isEmpty { return true }
        if attendees.contains(where: { $0.isSelf && $0.isOrganizer }) { return true }
        return organizer.map { own.contains($0.email.lowercased()) } ?? false
    }

    /// The same event with the user's answer set to `response`, in
    /// `selfResponse` and in the attendee list.
    public func answering(_ response: ResponseStatus) -> CalendarEvent {
        CalendarEvent(
            id: id, iCalUID: iCalUID, accountEmail: accountEmail, calendarID: calendarID,
            colorHex: colorHex, title: title, start: start, end: end, isAllDay: isAllDay,
            location: location, notes: notes, htmlLink: htmlLink, organizer: organizer,
            attendees: attendees.map { a in
                a.isSelf
                    ? Attendee(person: a.person, response: response, isOrganizer: a.isOrganizer,
                               isSelf: true, isOptional: a.isOptional)
                    : a
            },
            attachments: attachments, meeting: meeting, selfResponse: response,
            googleEventID: googleEventID
        )
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
    /// The user may add events (`accessRole` owner or writer). Nil for a
    /// calendar stored before this was known: only the primary counts then.
    public var canWrite: Bool?

    public init(id: String, name: String, colorHex: String, isPrimary: Bool, enabled: Bool, canWrite: Bool? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isPrimary = isPrimary
        self.enabled = enabled
        self.canWrite = canWrite
    }

    /// Where a new event can go.
    public var isWritable: Bool { canWrite ?? isPrimary }
}

public struct Account: Identifiable, Equatable, Codable, Sendable {
    public var id: String { email }
    public let email: String
    public var calendars: [CalendarInfo]
    /// The refresh token was revoked or expired: the user must sign in again.
    public var needsReconnect: Bool
    /// Scopes Google granted, from the last token response. `nil` for an
    /// account saved before Calbar recorded them.
    public var grantedScopes: [String]?

    public init(email: String, calendars: [CalendarInfo], needsReconnect: Bool, grantedScopes: [String]? = nil) {
        self.email = email
        self.calendars = calendars
        self.needsReconnect = needsReconnect
        self.grantedScopes = grantedScopes
    }

    /// Calbar may answer invitations for this account. An account signed in
    /// when Calbar only asked for read access must reconnect first.
    /// Google sources of guest suggestions this account was granted.
    public var contactSources: [PeopleAPI.Source] { PeopleAPI.sources(granted: grantedScopes) }

    public var canReply: Bool {
        (grantedScopes ?? []).contains { GoogleOAuth.writeScopes.contains($0) }
    }

    /// Google refused a write for lack of scope.
    public mutating func markReadOnly() {
        grantedScopes = (grantedScopes ?? []).filter { !GoogleOAuth.writeScopes.contains($0) }
    }
}
