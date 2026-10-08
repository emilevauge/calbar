import Foundation

/// An event to create from the hour grid.
public struct NewEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var calendarID: String
    public var addMeet: Bool
    public var location: String
    public var notes: String
    /// Guest emails; Google sends them the invitation.
    public var guests: [String]
    /// A Zoom meeting created for this event: its link goes to the
    /// location when that is empty, and on top of the description.
    public var zoom: ZoomMeeting?
    /// IANA name, so Google shows the times in the user's zone.
    public var timeZone: String
    /// `RRULE:` lines; empty for a single event.
    public var recurrence: [String] = []
    /// Whole days: `start` and `end` are midnights, the end excluded.
    public var isAllDay = false
    /// Meeting room emails, booked as resource attendees.
    public var rooms: [String] = []

    public init(title: String, start: Date, end: Date, calendarID: String, addMeet: Bool,
                location: String = "", notes: String = "", guests: [String] = [],
                timeZone: String = TimeZone.current.identifier) {
        self.title = title
        self.start = start
        self.end = end
        self.calendarID = calendarID
        self.addMeet = addMeet
        self.location = location
        self.notes = notes
        self.guests = guests
        self.timeZone = timeZone
    }

    /// Emails in free text, separated by commas, semicolons, spaces or
    /// new lines; "Name <email>" keeps the email. Duplicates dropped.
    public static func guests(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { ",; \n\t".contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()")) }
            .filter { $0.contains("@") && $0.contains(".") && seen.insert($0.lowercased()).inserted }
    }

    /// "(No title)" for a blank title, like Google Calendar.
    public var summary: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(No title)" : trimmed
    }

    /// The `events.insert` body. `requestId` must be unique per Meet link
    /// request; `id` keeps a retry of the same draft from asking twice.
    public func body(requestID: String = UUID().uuidString) throws -> Data {
        var json: [String: Any] = ["summary": summary]
        json["start"] = time(start)
        json["end"] = time(end)
        if !recurrence.isEmpty { json["recurrence"] = recurrence }
        var place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let zoom {
            if place.isEmpty { place = zoom.joinURL.absoluteString }
            text = text.isEmpty ? zoom.description : zoom.description + "\n\n" + text
        }
        if !place.isEmpty { json["location"] = place }
        if !text.isEmpty { json["description"] = text }
        let attendees: [[String: Any]] = guests.map { ["email": $0] } + rooms.map { ["email": $0, "resource": true] }
        if !attendees.isEmpty { json["attendees"] = attendees }
        if addMeet {
            json["conferenceData"] = ["createRequest": [
                "requestId": requestID,
                "conferenceSolutionKey": ["type": "hangoutsMeet"],
            ]]
        }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    /// A start or end in Google's form: a day for an all-day event, else
    /// a time with the zone, which recurring events need.
    func time(_ date: Date, calendar: Calendar = .current) -> [String: String] {
        isAllDay ? ["date": GoogleDate.day(date, calendar: calendar)]
                 : ["dateTime": GoogleDate.rfc3339(date), "timeZone": timeZone]
    }

    /// Start and end minutes of a slot dragged between two points of the
    /// grid, in either direction: the start down to the quarter hour, the
    /// end up to it, at least 15 minutes, within the day. A click (no real
    /// drag) gives `defaultMinutes` from the slot under the pointer.
    public static func range(from a: Double, to b: Double, step: Int = 15,
                             dragThreshold: Double = 8, defaultMinutes: Int = 30) -> (start: Int, end: Int) {
        if abs(b - a) < dragThreshold {
            let start = slot(minute: a, step: step)
            return (start, start + defaultMinutes)
        }
        let low = min(a, b), high = max(a, b)
        let start = min(max(Int(low) - Int(low) % step, 0), 24 * 60 - step)
        let up = Int(high.rounded(.up))
        let end = min(max(up % step == 0 ? up : up + step - up % step, start + step), 24 * 60)
        return (start, end)
    }

    /// Minute of the day under the pointer, down to the quarter hour, kept
    /// so that a default 30 minute event ends by midnight.
    public static func slot(minute: Double, step: Int = 15) -> Int {
        let m = Int(minute.rounded(.down))
        return min(max(m - m % step, 0), 24 * 60 - 30)
    }
}
