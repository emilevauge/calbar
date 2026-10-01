import Foundation
import Testing
@testable import CalbarCore

@Suite struct DeleteTests {
    let own: Set<String> = ["me@example.com"]

    func event(organizer: String?, attendees: [(String, Bool, Bool)], calendar: String = "me@example.com") -> CalendarEvent {
        let base = CalendarEvent.fixture(start: TestClock.date("2026-10-01T10:00:00+02:00"))
        return CalendarEvent(
            id: "e", iCalUID: "e", accountEmail: "me@example.com", calendarID: calendar, colorHex: "#000",
            title: "x", start: base.start, end: base.end, isAllDay: false, location: nil, notes: nil, htmlLink: nil,
            organizer: organizer.map { Person(email: $0, name: nil) },
            attendees: attendees.map { Attendee(person: Person(email: $0.0, name: nil), response: .accepted,
                                                isOrganizer: $0.1, isSelf: $0.2, isOptional: false) },
            attachments: [], meeting: nil, selfResponse: .accepted)
    }

    @Test func ownEventsOnly() {
        #expect(event(organizer: "me@example.com", attendees: []).isDeletable(own: own))
        #expect(event(organizer: nil, attendees: []).isDeletable(own: own))
        #expect(event(organizer: "me@example.com", attendees: [("me@example.com", true, true), ("a@x.io", false, false)]).isDeletable(own: own))
        // Someone else's invitation: declining, not deleting.
        #expect(!event(organizer: "boss@x.io", attendees: [("boss@x.io", true, false), ("me@example.com", false, true)]).isDeletable(own: own))
        // A colleague's shared calendar.
        let shared = event(organizer: "c@x.io", attendees: [], calendar: "c@x.io")
        #expect(!CalendarEvent(id: "s", iCalUID: "s", accountEmail: "me@example.com", calendarID: "c@x.io", colorHex: "#000",
                               title: "x", start: shared.start, end: shared.end, isAllDay: false, location: nil, notes: nil,
                               htmlLink: nil, organizer: shared.organizer, attendees: [], attachments: [], meeting: nil,
                               selfResponse: .accepted).isDeletable(own: ["other@example.com"]))
    }
}
