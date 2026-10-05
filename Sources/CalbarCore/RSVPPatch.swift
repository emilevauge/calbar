import Foundation

/// Body of the PATCH that answers an invitation.
///
/// PATCH replaces the attendee list as a whole, so the list sent back must
/// be the one Google has, with only the user's `responseStatus` changed.
/// Attendees are kept as raw JSON objects: comments, extra guests, meeting
/// rooms and any field added to the API later go back untouched.
public enum RSVPPatch {
    public enum Failure: Error, Equatable {
        /// No attendee with `self: true`, or the user organizes the event.
        case notInvited
        /// Only yes, maybe and no can be sent.
        case invalidResponse
    }

    public static func body(event: Data, response: ResponseStatus) throws -> Data {
        guard response != .needsAction else { throw Failure.invalidResponse }
        struct Event: Decodable {
            let attendees: [[String: JSONValue]]?
        }
        var attendees = try JSONDecoder().decode(Event.self, from: event).attendees ?? []
        guard let index = attendees.firstIndex(where: { $0["self"] == .bool(true) }),
              attendees[index]["organizer"] != .bool(true) else { throw Failure.notInvited }
        attendees[index]["responseStatus"] = .string(response.rawValue)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(["attendees": attendees])
    }

    /// Body of the PATCH that proposes another time to the organizer: the
    /// API has no "propose a new time", so the user's answer gets a note
    /// with the time, which Google emails to the organizer with the
    /// answer. A pending answer becomes "maybe", as Google Calendar does.
    public static func proposal(event: Data, start: Date, end: Date, timeZone: TimeZone = .current) throws -> Data {
        struct Event: Decodable {
            let attendees: [[String: JSONValue]]?
        }
        var attendees = try JSONDecoder().decode(Event.self, from: event).attendees ?? []
        guard let index = attendees.firstIndex(where: { $0["self"] == .bool(true) }),
              attendees[index]["organizer"] != .bool(true) else { throw Failure.notInvited }
        if attendees[index]["responseStatus"] == nil || attendees[index]["responseStatus"] == .string("needsAction") {
            attendees[index]["responseStatus"] = .string(ResponseStatus.tentative.rawValue)
        }
        attendees[index]["comment"] = .string(proposalNote(start: start, end: end, timeZone: timeZone))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(["attendees": attendees])
    }

    /// "Proposed new time: Tue, Oct 6, 14:00-14:45 (GMT+2)".
    public static func proposalNote(start: Date, end: Date, timeZone: TimeZone = .current) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "EEE, MMM d, HH:mm"
        let hour = DateFormatter()
        hour.locale = day.locale
        hour.timeZone = timeZone
        hour.dateFormat = "HH:mm"
        let zone = DateFormatter()
        zone.locale = day.locale
        zone.timeZone = timeZone
        zone.dateFormat = "O"
        return "Proposed new time: \(day.string(from: start))-\(hour.string(from: end)) (\(zone.string(from: start)))"
    }
}
