import Foundation
import Testing
@testable import CalbarCore

@Suite struct NotificationPlannerTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")
    let policy = AlertPolicy(leadTime: 600, lingerAfterStart: 300)

    func event(inMinutes m: Double, allDay: Bool = false, response: ResponseStatus = .accepted) -> CalendarEvent {
        .fixture(start: now.addingTimeInterval(m * 60), allDay: allDay, response: response)
    }

    func due(_ e: CalendarEvent, at date: Date? = nil, skip: Set<String> = []) -> Bool {
        !NotificationPlanner.due([e], now: date ?? now, policy: policy, skip: skip).isEmpty
    }

    @Test func respectsLeadTime() {
        #expect(!due(event(inMinutes: 11)))
        #expect(due(event(inMinutes: 10)))
        #expect(due(event(inMinutes: 3)))
    }

    @Test func firesOncePerOccurrence() {
        let e = event(inMinutes: 5)
        #expect(due(e))
        #expect(!due(e, skip: [e.occurrenceKey]))
        // Still inside the window a tick later: skipped all the same.
        #expect(!due(e, at: now.addingTimeInterval(15), skip: [e.occurrenceKey]))
    }

    @Test func notForStartedMeetings() {
        #expect(!due(event(inMinutes: 0)))
        #expect(!due(event(inMinutes: -2)))
    }

    @Test func notForDeclinedOrAllDay() {
        #expect(!due(event(inMinutes: 5, response: .declined)))
        #expect(!due(event(inMinutes: 5, allDay: true)))
    }

    @Test func firesAgainForMovedMeeting() {
        let before = CalendarEvent.fixture(id: "a", start: now.addingTimeInterval(5 * 60))
        let moved = CalendarEvent.fixture(id: "a", start: now.addingTimeInterval(8 * 60))
        #expect(before.occurrenceKey != moved.occurrenceKey)
        #expect(due(moved, skip: [before.occurrenceKey]))
    }

    @Test func earliestFirst() {
        let late = event(inMinutes: 8), early = event(inMinutes: 2)
        let result = NotificationPlanner.due([late, early], now: now, policy: policy, skip: [])
        #expect(result.map(\.id) == [early.id, late.id])
    }

    @Test func windowEndsAtLingerOrEnd() {
        let e = CalendarEvent.fixture(start: now, minutes: 30)
        #expect(NotificationPlanner.windowEnd(e, policy: policy) == now.addingTimeInterval(300))
        let short = CalendarEvent.fixture(start: now, minutes: 3)
        #expect(NotificationPlanner.windowEnd(short, policy: policy) == now.addingTimeInterval(180))
    }

    func dueAtStart(_ e: CalendarEvent, at date: Date? = nil, skip: Set<String> = []) -> Bool {
        !NotificationPlanner.dueAtStart([e], now: date ?? now, policy: policy, skip: skip).isEmpty
    }

    @Test func startFiresFromTheStartToTheEndOfTheWindow() {
        #expect(!dueAtStart(event(inMinutes: 0.5)))
        #expect(dueAtStart(event(inMinutes: 0)))
        #expect(dueAtStart(event(inMinutes: -4)))
        #expect(!dueAtStart(event(inMinutes: -5)))
    }

    @Test func startFiresOnceAndNotForDeclinedOrAllDay() {
        let e = event(inMinutes: 0)
        #expect(!dueAtStart(e, skip: [e.occurrenceKey]))
        #expect(!dueAtStart(event(inMinutes: 0, response: .declined)))
        #expect(!dueAtStart(event(inMinutes: 0, allDay: true)))
    }

}

@Suite struct WholeDayTests {
    @Test func longTimedEventsAreNotMeetings() {
        let start = TestClock.date("2026-10-06T00:00:00+02:00")
        let ooo = CalendarEvent.fixture(title: "Matt - OOO", start: start, minutes: 3 * 24 * 60)
        #expect(ooo.isWholeDay)
        let policy = AlertPolicy(leadTime: 600, lingerAfterStart: 300)
        #expect(NotificationPlanner.dueAtStart([ooo], now: start.addingTimeInterval(60), policy: policy, skip: []).isEmpty)
        #expect(NotificationPlanner.due([ooo], now: start.addingTimeInterval(-60), policy: policy, skip: []).isEmpty)
        #expect(NextMeeting.ongoing(events: [ooo], now: start.addingTimeInterval(3600)) == nil)
        let listing = DayListing.build(events: [ooo], day: start, calendar: TestClock.paris)
        #expect(listing.allDay.map(\.title) == ["Matt - OOO"])
        #expect(listing.timed.isEmpty)
    }
}
