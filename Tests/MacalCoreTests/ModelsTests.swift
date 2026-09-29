import Foundation
import Testing
@testable import MacalCore

@Suite struct ModelsTests {
    @Test func parsesHexColor() throws {
        let rgb = try #require(RGB(hex: "#ff8000"))
        #expect(rgb.red == 1)
        #expect(abs(rgb.green - 128.0 / 255.0) < 0.0001)
        #expect(rgb.blue == 0)
    }

    @Test func parsesHexWithoutHash() {
        #expect(RGB(hex: "000000") != nil)
    }

    @Test func rejectsInvalidHex() {
        #expect(RGB(hex: "#fff") == nil)
        #expect(RGB(hex: "zzzzzz") == nil)
    }

    @Test func occurrenceKeyChangesWhenEventMoves() {
        let start = TestClock.date("2026-09-29T10:00:00+02:00")
        let a = CalendarEvent.fixture(id: "x", start: start)
        let b = CalendarEvent.fixture(id: "x", start: start.addingTimeInterval(900))
        #expect(a.occurrenceKey != b.occurrenceKey)
    }

    @Test func webURLAddsAuthUser() throws {
        var event = CalendarEvent.fixture(account: "alice@example.com", start: Date())
        event = CalendarEvent(
            id: event.id, iCalUID: event.iCalUID, accountEmail: event.accountEmail,
            calendarID: event.calendarID, colorHex: event.colorHex, title: event.title,
            start: event.start, end: event.end, isAllDay: false, location: nil, notes: nil,
            htmlLink: URL(string: "https://www.google.com/calendar/event?eid=abc"),
            organizer: nil, attendees: [], attachments: [], meeting: nil, selfResponse: .accepted
        )
        let url = try #require(event.webURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "eid", value: "abc")))
        #expect(items.contains(URLQueryItem(name: "authuser", value: "alice@example.com")))
    }

    @Test func fullEventSurvivesCodableRoundTrip() throws {
        let event = CalendarEvent(
            id: "me@x.com/me@x.com/abc", iCalUID: "abc@google.com", accountEmail: "me@x.com",
            calendarID: "me@x.com", colorHex: "#9fe1e7", title: "Traefik x Acme call",
            start: TestClock.date("2026-09-29T10:30:00+02:00"), end: TestClock.date("2026-09-29T11:00:00+02:00"),
            isAllDay: false, location: "Everest room", notes: "<b>Agenda</b>",
            htmlLink: URL(string: "https://www.google.com/calendar/event?eid=abc"),
            organizer: Person(email: "bob@acme.com", name: "Bob"),
            attendees: [
                Attendee(person: Person(email: "bob@acme.com", name: "Bob"), response: .accepted, isOrganizer: true, isSelf: false, isOptional: false),
                Attendee(person: Person(email: "me@x.com", name: nil), response: .tentative, isOrganizer: false, isSelf: true, isOptional: true),
            ],
            attachments: [
                Attachment(title: "Notes", url: URL(string: "https://docs.google.com/document/d/xyz")!,
                           mimeType: "application/vnd.google-apps.document", iconURL: URL(string: "https://drive.example/icon.png")),
            ],
            meeting: MeetingLink(url: URL(string: "https://zoom.us/j/1?pwd=a%2Bb")!, provider: .zoom),
            selfResponse: .tentative
        )
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(CalendarEvent.self, from: data) == event)
    }
}
