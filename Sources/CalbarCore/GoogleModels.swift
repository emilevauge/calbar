import Foundation

// Wire formats of the Google Calendar API v3, reduced to the fields we use.

struct GoogleEvent: Decodable {
    struct Time: Decodable {
        let dateTime: String?
        let date: String?
    }

    struct Participant: Decodable {
        let email: String?
        let displayName: String?
        let isSelf: Bool?
        let organizer: Bool?
        let responseStatus: String?
        let optional: Bool?
        let resource: Bool?

        enum CodingKeys: String, CodingKey {
            case email, displayName, organizer, responseStatus, optional, resource
            case isSelf = "self"
        }
    }

    struct File: Decodable {
        let fileUrl: String
        let title: String?
        let mimeType: String?
        let iconLink: String?
    }

    struct Conference: Decodable {
        struct EntryPoint: Decodable {
            let entryPointType: String
            let uri: String
        }
        let entryPoints: [EntryPoint]?
    }

    let id: String
    let iCalUID: String?
    let status: String?
    let summary: String?
    let description: String?
    let location: String?
    let htmlLink: String?
    /// Missing on cancelled instances of a recurring event, which only
    /// carry their id and status.
    let start: Time?
    let end: Time?
    let attendees: [Participant]?
    let organizer: Participant?
    let hangoutLink: String?
    let conferenceData: Conference?
    let attachments: [File]?
    let eventType: String?
}

struct GoogleEventList: Decodable {
    let items: [GoogleEvent]
    let nextPageToken: String?
}

struct GoogleCalendarList: Decodable {
    struct Entry: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
        let selected: Bool?
        let primary: Bool?
        let accessRole: String?
    }
    let items: [Entry]
    let nextPageToken: String?
}

enum GoogleDate {
    /// Start or end of an event, and whether it is a whole-day date.
    static func parse(_ time: GoogleEvent.Time, calendar: Calendar) -> (date: Date, allDay: Bool)? {
        if let s = time.dateTime { return dateTime(s).map { ($0, false) } }
        if let s = time.date { return day(s, calendar: calendar).map { ($0, true) } }
        return nil
    }

    // Configured once, then only read: ISO8601DateFormatter is thread-safe
    // for parsing and formatting.
    private static let internetDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let internetDateTimeFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let utcOutput: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func dateTime(_ s: String) -> Date? {
        internetDateTime.date(from: s) ?? internetDateTimeFractional.date(from: s)
    }

    /// "2026-09-29" as local midnight: an all-day event covers the user's
    /// day, not a UTC one. Impossible dates such as "2026-13-45" are
    /// rejected instead of rolling over into another day.
    static func day(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == parts[0], back.month == parts[1], back.day == parts[2] else { return nil }
        return date
    }

    static func rfc3339(_ date: Date) -> String {
        utcOutput.string(from: date)
    }
}

extension CalendarEvent {
    /// `nil` for events we never show: cancelled ones and the "working
    /// location" markers Google adds to every day.
    init?(google g: GoogleEvent, accountEmail: String, source: CalendarInfo, calendar: Calendar) {
        guard g.status != "cancelled", g.eventType != "workingLocation",
              let startTime = g.start, let endTime = g.end,
              let start = GoogleDate.parse(startTime, calendar: calendar),
              let end = GoogleDate.parse(endTime, calendar: calendar) else { return nil }

        // Meeting rooms show up as attendees with `resource: true`.
        let attendees: [Attendee] = (g.attendees ?? [])
            .filter { $0.resource != true }
            .compactMap { p in
                guard let email = p.email else { return nil }
                return Attendee(
                    person: Person(email: email, name: p.displayName),
                    response: ResponseStatus(google: p.responseStatus),
                    isOrganizer: p.organizer == true,
                    isSelf: p.isSelf == true,
                    isOptional: p.optional == true
                )
            }

        let videoURIs = (g.conferenceData?.entryPoints ?? [])
            .filter { $0.entryPointType == "video" }
            .map(\.uri)

        let title = g.summary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "(No title)"

        self.init(
            id: "\(accountEmail)/\(source.id)/\(g.id)",
            iCalUID: g.iCalUID ?? g.id,
            accountEmail: accountEmail,
            calendarID: source.id,
            colorHex: source.colorHex,
            title: title,
            start: start.date,
            end: end.date,
            isAllDay: start.allDay,
            location: g.location,
            notes: g.description,
            htmlLink: g.htmlLink.flatMap(URL.init(string:)),
            organizer: g.organizer.flatMap { o in o.email.map { Person(email: $0, name: o.displayName) } },
            attendees: attendees,
            attachments: (g.attachments ?? []).compactMap { a in
                URL(string: a.fileUrl).map {
                    Attachment(title: a.title ?? a.fileUrl, url: $0, mimeType: a.mimeType,
                               iconURL: a.iconLink.flatMap(URL.init(string:)))
                }
            },
            meeting: MeetingLinkExtractor.extract(
                conferenceURIs: videoURIs, hangoutLink: g.hangoutLink,
                location: g.location, description: g.description
            ),
            selfResponse: attendees.first(where: \.isSelf)?.response ?? .accepted,
            googleEventID: g.id
        )
    }
}

extension CalendarInfo {
    /// Only the account's main calendar starts enabled. The other ones,
    /// even when checked in the Google Calendar web UI, stay off until the
    /// user turns them on in the settings.
    init(google e: GoogleCalendarList.Entry) {
        self.init(
            id: e.id,
            name: e.summaryOverride ?? e.summary ?? e.id,
            colorHex: e.backgroundColor ?? "#4285f4",
            isPrimary: e.primary == true,
            enabled: e.primary == true,
            canWrite: e.accessRole.map { $0 == "owner" || $0 == "writer" }
        )
    }
}
