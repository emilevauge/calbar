import Foundation
import Testing
@testable import CalbarCore

@Suite struct GoogleCalendarWebTests {
    @Test func homeWithoutAccount() {
        #expect(GoogleCalendarWeb.home(authuser: nil).absoluteString == "https://calendar.google.com/calendar/r")
        #expect(GoogleCalendarWeb.home(authuser: "").absoluteString == "https://calendar.google.com/calendar/r")
    }

    @Test func homePinsTheAccount() {
        let url = GoogleCalendarWeb.home(authuser: "alice@example.com")
        #expect(url.absoluteString == "https://calendar.google.com/calendar/r?authuser=alice%40example.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items == [URLQueryItem(name: "authuser", value: "alice@example.com")])
    }

    @Test func plusSignIsEncoded() {
        let url = GoogleCalendarWeb.home(authuser: "me+cal@example.com")
        #expect(url.absoluteString.hasSuffix("authuser=me%2Bcal%40example.com"))
    }

    @Test func eventLinkEncodesPlusToo() throws {
        let base = CalendarEvent.fixture(account: "me+cal@example.com", start: Date())
        let event = CalendarEvent(
            id: base.id, iCalUID: base.iCalUID, accountEmail: base.accountEmail,
            calendarID: base.calendarID, colorHex: base.colorHex, title: base.title,
            start: base.start, end: base.end, isAllDay: false, location: nil, notes: nil,
            htmlLink: URL(string: "https://www.google.com/calendar/event?eid=abc"),
            organizer: nil, attendees: [], attachments: [], meeting: nil, selfResponse: .accepted
        )
        let url = try #require(event.webURL)
        #expect(url.absoluteString == "https://www.google.com/calendar/event?eid=abc&authuser=me%2Bcal%40example.com")
    }
}
