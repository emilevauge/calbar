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
}
