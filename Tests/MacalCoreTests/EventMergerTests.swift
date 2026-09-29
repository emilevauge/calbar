import Foundation
import Testing
@testable import MacalCore

@Suite struct EventMergerTests {
    let ten = TestClock.date("2026-09-29T10:00:00+02:00")
    let zoom = MeetingLink(url: URL(string: "https://zoom.us/j/1")!, provider: .zoom)

    @Test func deduplicatesSameMeetingSeenFromTwoAccounts() {
        let a = CalendarEvent.fixture(id: "a", iCalUID: "m@g", account: "perso@gmail.com", start: ten)
        let b = CalendarEvent.fixture(id: "b", iCalUID: "m@g", account: "work@example.com", start: ten, meeting: zoom)
        let merged = EventMerger.merge([a, b], showDeclined: false)
        #expect(merged.map(\.id) == ["b"])
    }

    @Test func keepsEachOccurrenceOfRecurringMeeting() {
        let a = CalendarEvent.fixture(id: "a", iCalUID: "daily@g", start: ten)
        let b = CalendarEvent.fixture(id: "b", iCalUID: "daily@g", start: ten.addingTimeInterval(86_400))
        #expect(EventMerger.merge([a, b], showDeclined: false).count == 2)
    }

    @Test func prefersNonDeclinedCopy() {
        let declined = CalendarEvent.fixture(id: "a", iCalUID: "m", start: ten, response: .declined, meeting: zoom)
        let accepted = CalendarEvent.fixture(id: "b", iCalUID: "m", start: ten)
        #expect(EventMerger.merge([declined, accepted], showDeclined: true).map(\.id) == ["b"])
    }

    @Test func hidesDeclinedUnlessAsked() {
        let e = CalendarEvent.fixture(id: "a", start: ten, response: .declined)
        #expect(EventMerger.merge([e], showDeclined: false).isEmpty)
        #expect(EventMerger.merge([e], showDeclined: true).count == 1)
    }

    @Test func sortsByStartThenTitle() {
        let late = CalendarEvent.fixture(id: "1", title: "Z", start: ten.addingTimeInterval(3600))
        let b = CalendarEvent.fixture(id: "2", title: "B", start: ten)
        let a = CalendarEvent.fixture(id: "3", title: "A", start: ten)
        #expect(EventMerger.merge([late, b, a], showDeclined: false).map(\.title) == ["A", "B", "Z"])
    }

    // Google marks as `self` the owner of the calendar a copy lives on:
    // the copy on a colleague's shared calendar says "accepted" even when
    // the signed-in user declined.
    @Test func primaryCalendarCopyWinsOverSharedCalendarCopy() {
        let mine = CalendarEvent.fixture(id: "a", iCalUID: "m", account: "me@x.com", start: ten, response: .declined)
        let shared = CalendarEvent.fixture(
            id: "b", iCalUID: "m", account: "me@x.com", calendarID: "boss@x.com", start: ten, meeting: zoom
        )
        #expect(EventMerger.merge([shared, mine], showDeclined: false).isEmpty)
        #expect(EventMerger.merge([mine, shared], showDeclined: true).map(\.id) == ["a"])
    }

    @Test func equalScoreKeepsSmallerID() {
        let a = CalendarEvent.fixture(id: "a", iCalUID: "m", start: ten)
        let b = CalendarEvent.fixture(id: "b", iCalUID: "m", start: ten)
        #expect(EventMerger.merge([a, b], showDeclined: false).map(\.id) == ["a"])
        #expect(EventMerger.merge([b, a], showDeclined: false).map(\.id) == ["a"])
    }
}
