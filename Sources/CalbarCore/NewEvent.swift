import Foundation

/// An event to create from the hour grid.
public struct NewEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var calendarID: String
    public var addMeet: Bool
    /// IANA name, so Google shows the times in the user's zone.
    public var timeZone: String

    public init(title: String, start: Date, end: Date, calendarID: String, addMeet: Bool,
                timeZone: String = TimeZone.current.identifier) {
        self.title = title
        self.start = start
        self.end = end
        self.calendarID = calendarID
        self.addMeet = addMeet
        self.timeZone = timeZone
    }

    /// "(No title)" for a blank title, like Google Calendar.
    public var summary: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(No title)" : trimmed
    }

    /// The `events.insert` body. `requestId` must be unique per Meet link
    /// request; `id` keeps a retry of the same draft from asking twice.
    public func body(requestID: String = UUID().uuidString) throws -> Data {
        var json: [String: Any] = [
            "summary": summary,
            "start": ["dateTime": GoogleDate.rfc3339(start), "timeZone": timeZone],
            "end": ["dateTime": GoogleDate.rfc3339(end), "timeZone": timeZone],
        ]
        if addMeet {
            json["conferenceData"] = ["createRequest": [
                "requestId": requestID,
                "conferenceSolutionKey": ["type": "hangoutsMeet"],
            ]]
        }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    /// Minute of the day under the pointer, down to the quarter hour, kept
    /// so that a default 30 minute event ends by midnight.
    public static func slot(minute: Double, step: Int = 15) -> Int {
        let m = Int(minute.rounded(.down))
        return min(max(m - m % step, 0), 24 * 60 - 30)
    }
}
