import Foundation
import Testing
@testable import CalbarCore

@Suite struct ContactIndexTests {
    func meeting(_ people: [(String, String?)], me: String = "me@example.com") -> CalendarEvent {
        var e = CalendarEvent.fixture(start: TestClock.date("2026-10-01T10:00:00+02:00"))
        let attendees = people.map {
            Attendee(person: Person(email: $0.0, name: $0.1), response: .accepted,
                     isOrganizer: false, isSelf: false, isOptional: false)
        } + [Attendee(person: Person(email: me, name: "Me"), response: .accepted,
                      isOrganizer: false, isSelf: true, isOptional: false)]
        e = CalendarEvent(id: UUID().uuidString, iCalUID: e.iCalUID, accountEmail: me, calendarID: me,
                          colorHex: e.colorHex, title: e.title, start: e.start, end: e.end, isAllDay: false,
                          location: nil, notes: nil, htmlLink: nil, organizer: nil, attendees: attendees,
                          attachments: [], meeting: nil, selfResponse: .accepted)
        return e
    }

    @Test func searchesNameWordsAndEmails() {
        var index = ContactIndex()
        index.add(events: [meeting([("alice.martin@example.com", "Alice Martin"), ("bob@example.com", "Bob Chen")])],
                  excluding: ["me@example.com"])
        #expect(index.search("ali").map(\.email) == ["alice.martin@example.com"])
        #expect(index.search("mart").map(\.email) == ["alice.martin@example.com"])
        #expect(index.search("bob@").map(\.email) == ["bob@example.com"])
        #expect(index.search("me").isEmpty)
        #expect(index.search("").isEmpty)
    }

    @Test func frequentPeopleFirstAndAccentsIgnored() {
        var index = ContactIndex()
        index.add(events: [
            meeting([("eloise@example.com", "Éloïse Dupont"), ("elodie@example.com", "Elodie Roux")]),
            meeting([("elodie@example.com", "Elodie Roux")]),
        ], excluding: [])
        #expect(index.search("el").map(\.email) == ["elodie@example.com", "eloise@example.com"])
        #expect(index.search("eloi").map(\.email) == ["eloise@example.com"])
    }

    @Test func addressBookAndExclusions() {
        var index = ContactIndex()
        index.add(contacts: [.init(email: "carla@example.com", name: "Carla Diaz"), .init(email: "dan@example.com", name: nil)])
        #expect(index.search("car").first?.label == "Carla Diaz <carla@example.com>")
        #expect(index.search("dan").first?.label == "dan@example.com")
        #expect(index.search("car", excluding: ["CARLA@example.com"]).isEmpty)
    }
}
