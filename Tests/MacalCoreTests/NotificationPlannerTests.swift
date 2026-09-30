import Foundation
import Testing
@testable import MacalCore

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

    @Test func body() {
        let url = URL(string: "https://zoom.us/j/1")!
        let withLink = CalendarEvent.fixture(start: TestClock.date("2026-09-29T11:05:00+02:00"), minutes: 60,
                                             meeting: MeetingLink(url: url, provider: .zoom))
        #expect(NotificationPlanner.body(withLink, now: now, calendar: TestClock.paris) == "In 5 min · 11:05-12:05 · Zoom")
        let noLink = CalendarEvent.fixture(start: TestClock.date("2026-09-29T11:05:00+02:00"), minutes: 60)
        #expect(NotificationPlanner.body(noLink, now: now, calendar: TestClock.paris) == "In 5 min · 11:05-12:05")
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

    @Test func startBody() {
        let e = CalendarEvent.fixture(start: now, minutes: 30)
        #expect(NotificationPlanner.body(e, now: now, calendar: TestClock.paris) == "Starting now · 11:00-11:30")
        #expect(NotificationPlanner.body(e, now: now.addingTimeInterval(59), calendar: TestClock.paris)
            == "Starting now · 11:00-11:30")
        #expect(NotificationPlanner.body(e, now: now.addingTimeInterval(190), calendar: TestClock.paris)
            == "Started 3 min ago · 11:00-11:30")
    }
}
