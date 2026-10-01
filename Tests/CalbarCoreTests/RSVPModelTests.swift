import Foundation
import Testing
@testable import CalbarCore

@Suite struct RSVPModelTests {
    let primary = CalendarInfo(id: "alice@example.com", name: "Alice", colorHex: "#9fe1e7", isPrimary: true, enabled: true)
    let shared = CalendarInfo(id: "bob@example.com", name: "Bob", colorHex: "#16a765", isPrimary: false, enabled: true)

    func event(_ attendees: String, on source: CalendarInfo? = nil) throws -> CalendarEvent {
        let json = #"""
        {"id": "abc_20260929T083000Z", "start": {"dateTime": "2026-09-29T10:00:00Z"},
         "end": {"dateTime": "2026-09-29T10:30:00Z"}, "attendees": \#(attendees)}
        """#
        let g = try JSONDecoder().decode(GoogleEvent.self, from: Data(json.utf8))
        return try #require(CalendarEvent(google: g, accountEmail: "alice@example.com",
                                          source: source ?? primary, calendar: TestClock.paris))
    }

    static let invited = #"""
    [{"email": "bob@acme.com", "organizer": true, "responseStatus": "accepted"},
     {"email": "alice@example.com", "self": true, "responseStatus": "needsAction"}]
    """#

    // MARK: event fields

    @Test func keepsTheRawGoogleID() throws {
        let e = try event(Self.invited)
        #expect(e.googleEventID == "abc_20260929T083000Z")
        #expect(e.id == "alice@example.com/alice@example.com/abc_20260929T083000Z")
    }

    @Test func inviteeCanRespond() throws {
        #expect(try event(Self.invited).canRespond)
    }

    @Test func organizerCannotRespond() throws {
        let json = #"[{"email": "alice@example.com", "self": true, "organizer": true, "responseStatus": "accepted"}, {"email": "bob@acme.com"}]"#
        #expect(try event(json).canRespond == false)
    }

    @Test func eventWithoutAttendeesCannotBeAnswered() throws {
        #expect(try event("[]").canRespond == false)
        #expect(try event(#"[{"email": "bob@acme.com", "responseStatus": "accepted"}]"#).canRespond == false)
    }

    @Test func copyOnAnotherCalendarCannotBeAnswered() throws {
        // On a shared calendar, `self` is the calendar owner: answering
        // would change a colleague's answer.
        #expect(try event(Self.invited, on: shared).canRespond == false)
    }

    @Test func cachedEventWithoutGoogleIDDerivesIt() throws {
        let e = try event(Self.invited)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        object["googleEventID"] = nil
        let old = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.googleEventID == "abc_20260929T083000Z")
        #expect(old == e)
        #expect(old.canRespond)
    }

    @Test func googleIDIsEncoded() throws {
        let e = try event(Self.invited)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        #expect(object["googleEventID"] as? String == "abc_20260929T083000Z")
    }

    @Test func fixtureDerivesTheGoogleID() {
        let e = CalendarEvent.fixture(id: "me@x.com/me@x.com/zzz", start: Date())
        #expect(e.googleEventID == "zzz")
        #expect(CalendarEvent.fixture(id: "plain", start: Date()).googleEventID == "plain")
    }

    // MARK: answering

    @Test func answeringUpdatesTheSelfAttendeeToo() throws {
        let e = try event(Self.invited)
        let answered = e.answering(.declined)
        #expect(answered.selfResponse == .declined)
        #expect(answered.attendees.map(\.response) == [.accepted, .declined])
        #expect(answered.id == e.id)
        #expect(answered.googleEventID == e.googleEventID)
        #expect(answered.answering(.needsAction).selfResponse == .needsAction)
    }

    // MARK: merging

    @Test func recentlyAnsweredDeclinedEventStaysVisible() {
        let start = TestClock.date("2026-09-29T10:00:00+02:00")
        let declined = CalendarEvent.fixture(id: "d", start: start, response: .declined)
        let other = CalendarEvent.fixture(id: "o", start: start.addingTimeInterval(60), response: .declined)
        #expect(EventMerger.merge([declined, other], showDeclined: false).isEmpty)
        #expect(EventMerger.merge([declined, other], showDeclined: false, keeping: ["d"]).map(\.id) == ["d"])
    }

    // MARK: scopes

    @Test func requestsTheEventsScope() {
        let scopes = GoogleOAuth.scopes.split(separator: " ").map(String.init)
        #expect(scopes == [
            "openid", "email",
            "https://www.googleapis.com/auth/calendar.readonly",
            "https://www.googleapis.com/auth/calendar.events",
        ])
    }

    @Test func tokenResponseCarriesGrantedScopes() throws {
        let json = #"{"access_token": "a", "expires_in": 3599, "scope": "openid https://www.googleapis.com/auth/calendar.readonly  https://www.googleapis.com/auth/userinfo.email", "token_type": "Bearer"}"#
        let tokens = try GoogleOAuth.parseTokenResponse(data: Data(json.utf8), status: 200)
        #expect(tokens.grantedScopes == [
            "openid", "https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/userinfo.email",
        ])
        let bare = try GoogleOAuth.parseTokenResponse(data: Data(#"{"access_token": "a", "expires_in": 1}"#.utf8), status: 200)
        #expect(bare.grantedScopes == nil)
    }

    @Test func canReplyNeedsAWriteScope() {
        func account(_ scopes: [String]?) -> Account {
            Account(email: "a@x.com", calendars: [], needsReconnect: false, grantedScopes: scopes)
        }
        #expect(account(nil).canReply == false)
        #expect(account(["openid", "https://www.googleapis.com/auth/calendar.readonly"]).canReply == false)
        #expect(account(["https://www.googleapis.com/auth/calendar.events"]).canReply)
        #expect(account(["https://www.googleapis.com/auth/calendar"]).canReply)
    }

    @Test func readOnlyAccountDropsWriteScopes() {
        var a = Account(email: "a@x.com", calendars: [], needsReconnect: false,
                        grantedScopes: ["openid", "https://www.googleapis.com/auth/calendar.events"])
        a.markReadOnly()
        #expect(a.grantedScopes == ["openid"])
        #expect(!a.canReply)
    }

    @Test func accountSavedBeforeScopesDecodes() throws {
        let json = #"[{"email": "a@x.com", "calendars": [], "needsReconnect": false}]"#
        let accounts = try JSONDecoder().decode([Account].self, from: Data(json.utf8))
        #expect(accounts.first?.grantedScopes == nil)
        #expect(accounts.first?.canReply == false)
        let a = Account(email: "a@x.com", calendars: [], needsReconnect: false, grantedScopes: ["x"])
        #expect(try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(a)) == a)
    }
}
