import Foundation
import Testing
@testable import CalbarCore

@Suite struct RSVPTests {
    /// An event as Google returns it, with attendee fields Calbar does not
    /// model, a meeting room, and the user invited by someone else.
    static let eventJSON = #"""
    {
      "kind": "calendar#event",
      "id": "abc123_20260929T083000Z",
      "summary": "Traefik x Acme call",
      "attendees": [
        {"email": "bob@acme.com", "displayName": "Bob", "organizer": true, "responseStatus": "accepted"},
        {"email": "alice@example.com", "self": true, "responseStatus": "needsAction",
         "comment": "Might be late", "additionalGuests": 2, "optional": false,
         "id": "p1", "extra": {"nested": [1, 2.5, null, "x"]}},
        {"email": "everest@resource.calendar.google.com", "displayName": "Everest", "resource": true,
         "responseStatus": "accepted"},
        {"email": "carol@acme.com", "responseStatus": "tentative", "optional": true}
      ]
    }
    """#

    static func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: JSON value

    @Test func jsonValueRoundTripsEveryKind() throws {
        let json = #"{"a": null, "b": true, "c": 2, "d": 2.5, "e": "s", "f": [1, "x"], "g": {"h": false}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(value == .object([
            "a": .null, "b": .bool(true), "c": .int(2), "d": .double(2.5), "e": .string("s"),
            "f": .array([.int(1), .string("x")]), "g": .object(["h": .bool(false)]),
        ]))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }

    @Test func integersStayIntegers() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["n": .int(2)]))
        #expect(String(decoding: data, as: UTF8.self) == #"{"n":2}"#)
    }

    // MARK: patch body

    @Test func patchBodyChangesOnlyTheSelfAnswer() throws {
        let body = try RSVPPatch.body(event: Data(Self.eventJSON.utf8), response: .accepted)
        let object = try Self.object(body)
        // Only the attendee list is sent: nothing else of the event changes.
        #expect(Array(object.keys) == ["attendees"])
        let attendees = try #require(object["attendees"] as? [[String: Any]])
        #expect(attendees.count == 4)
        #expect(attendees.map { $0["email"] as? String } == [
            "bob@acme.com", "alice@example.com", "everest@resource.calendar.google.com", "carol@acme.com",
        ])
        #expect(attendees.map { $0["responseStatus"] as? String } == ["accepted", "accepted", "accepted", "tentative"])

        // Every other field of the user's entry survives, unknown ones included.
        let me = attendees[1]
        #expect(me["comment"] as? String == "Might be late")
        #expect(me["additionalGuests"] as? Int == 2)
        #expect(me["optional"] as? Bool == false)
        #expect(me["self"] as? Bool == true)
        #expect(me["id"] as? String == "p1")
        let extra = try #require(me["extra"] as? [String: Any])
        let nested = try #require(extra["nested"] as? [Any])
        #expect(nested.count == 4)
        #expect(nested[1] as? Double == 2.5)
        #expect(nested[2] is NSNull)

        // The meeting room keeps its resource flag and name.
        #expect(attendees[2]["resource"] as? Bool == true)
        #expect(attendees[2]["displayName"] as? String == "Everest")
        #expect(attendees[3]["optional"] as? Bool == true)
    }

    @Test func patchBodyWritesEachAnswer() throws {
        for (response, raw) in [(ResponseStatus.accepted, "accepted"), (.tentative, "tentative"), (.declined, "declined")] {
            let body = try RSVPPatch.body(event: Data(Self.eventJSON.utf8), response: response)
            let attendees = try #require(try Self.object(body)["attendees"] as? [[String: Any]])
            #expect(attendees[1]["responseStatus"] as? String == raw)
        }
    }

    @Test func patchBodyRefusesAnEventWithoutSelfAttendee() {
        let json = #"{"attendees": [{"email": "bob@acme.com", "organizer": true, "responseStatus": "accepted"}]}"#
        #expect(throws: RSVPPatch.Failure.notInvited) {
            try RSVPPatch.body(event: Data(json.utf8), response: .accepted)
        }
        #expect(throws: RSVPPatch.Failure.notInvited) {
            try RSVPPatch.body(event: Data(#"{"id": "x"}"#.utf8), response: .accepted)
        }
    }

    @Test func patchBodyRefusesTheOrganizer() {
        let json = #"{"attendees": [{"email": "me@x.com", "self": true, "organizer": true, "responseStatus": "accepted"}]}"#
        #expect(throws: RSVPPatch.Failure.notInvited) {
            try RSVPPatch.body(event: Data(json.utf8), response: .declined)
        }
    }

    @Test func patchBodyRefusesNeedsAction() {
        #expect(throws: RSVPPatch.Failure.invalidResponse) {
            try RSVPPatch.body(event: Data(Self.eventJSON.utf8), response: .needsAction)
        }
    }

    // MARK: API

    @Test func respondGetsThenPatchesTheEvent() async throws {
        let http = StubHTTP([(200, Self.eventJSON), (200, #"{"id": "abc123_20260929T083000Z"}"#)])
        let api = CalendarAPI(http: http)
        try await api.respond(token: "tok", calendarID: "alice+work@example.com",
                              eventID: "abc123_20260929T083000Z", response: .declined)

        #expect(http.requests.count == 2)
        let get = http.requests[0]
        #expect(get.httpMethod == "GET")
        #expect(get.url?.absoluteString
            == "https://www.googleapis.com/calendar/v3/calendars/alice%2Bwork%40example.com/events/abc123_20260929T083000Z")
        #expect(get.value(forHTTPHeaderField: "Authorization") == "Bearer tok")

        let patch = http.requests[1]
        #expect(patch.httpMethod == "PATCH")
        #expect(patch.url?.absoluteString
            == "https://www.googleapis.com/calendar/v3/calendars/alice%2Bwork%40example.com/events/abc123_20260929T083000Z?sendUpdates=all")
        #expect(patch.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(patch.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try Self.object(try #require(patch.httpBody))
        let attendees = try #require(body["attendees"] as? [[String: Any]])
        #expect(attendees[1]["responseStatus"] as? String == "declined")
        #expect(attendees[1]["comment"] as? String == "Might be late")
    }

    @Test func respondEscapesTheEventID() async throws {
        let http = StubHTTP([(200, Self.eventJSON), (200, "{}")])
        try await CalendarAPI(http: http).respond(token: "t", calendarID: "c", eventID: "a/b+c", response: .accepted)
        #expect(http.requests[0].url?.absoluteString == "https://www.googleapis.com/calendar/v3/calendars/c/events/a%2Fb%2Bc")
    }

    @Test func respondMapsUnauthorized() async {
        let api = CalendarAPI(http: StubHTTP([(401, "{}")]))
        await #expect(throws: APIError.unauthorized) {
            try await api.respond(token: "old", calendarID: "c", eventID: "e", response: .accepted)
        }
    }

    static let scopeError = #"""
    {"error": {"code": 403, "message": "Request had insufficient authentication scopes.",
      "errors": [{"message": "Insufficient Permission", "domain": "global", "reason": "insufficientPermissions"}],
      "status": "PERMISSION_DENIED",
      "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT",
                   "domain": "googleapis.com"}]}}
    """#

    @Test func respondMapsInsufficientScopeOnPatch() async {
        let api = CalendarAPI(http: StubHTTP([(200, Self.eventJSON), (403, Self.scopeError)]))
        await #expect(throws: APIError.insufficientScope) {
            try await api.respond(token: "t", calendarID: "c", eventID: "e", response: .accepted)
        }
    }

    @Test func recognizesEitherScopeReason() {
        let legacy = #"{"error": {"code": 403, "errors": [{"reason": "insufficientPermissions"}]}}"#
        let modern = #"{"error": {"code": 403, "details": [{"reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#
        #expect(APIError.from(status: 403, body: Data(legacy.utf8)) == .insufficientScope)
        #expect(APIError.from(status: 403, body: Data(modern.utf8)) == .insufficientScope)
    }

    @Test func otherForbiddenStaysAnHTTPError() {
        let body = #"{"error": {"code": 403, "errors": [{"reason": "forbidden"}]}}"#
        #expect(APIError.from(status: 403, body: Data(body.utf8)) == .http(status: 403, body: body))
        #expect(APIError.from(status: 403, body: Data("not json".utf8)) == .http(status: 403, body: "not json"))
        #expect(APIError.from(status: 401, body: Data()) == .unauthorized)
        #expect(APIError.from(status: 500, body: Data("x".utf8)) == .http(status: 500, body: "x"))
    }

    @Test func respondRefusesWhenNotInvited() async {
        let http = StubHTTP([(200, #"{"attendees": []}"#)])
        await #expect(throws: RSVPPatch.Failure.notInvited) {
            try await CalendarAPI(http: http).respond(token: "t", calendarID: "c", eventID: "e", response: .accepted)
        }
        #expect(http.requests.count == 1)
    }

    @Test func proposalNoteAndAnswer() throws {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let start = TestClock.date("2026-10-06T14:00:00+02:00")
        #expect(RSVPPatch.proposalNote(start: start, end: start.addingTimeInterval(2700), timeZone: paris)
                == "Proposed new time: Tue, Oct 6, 14:00-14:45 (GMT+2)")
        let event = #"{"attendees": [{"email": "boss@x.com", "organizer": true}, {"email": "me@x.com", "self": true, "responseStatus": "needsAction"}]}"#
        let body = try RSVPPatch.proposal(event: Data(event.utf8), start: start, end: start.addingTimeInterval(2700), timeZone: paris)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let me = try #require((json["attendees"] as? [[String: Any]])?.last)
        #expect(me["responseStatus"] as? String == "tentative")
        #expect((me["comment"] as? String)?.hasPrefix("Proposed new time:") == true)
        let mine = #"{"attendees": [{"email": "me@x.com", "self": true, "organizer": true}]}"#
        #expect(throws: RSVPPatch.Failure.notInvited) {
            try RSVPPatch.proposal(event: Data(mine.utf8), start: start, end: start)
        }
    }
}
