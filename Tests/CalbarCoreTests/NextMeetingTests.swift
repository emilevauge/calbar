import Foundation
import Testing
@testable import CalbarCore

@Suite struct NextMeetingTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")

    func at(_ time: String, day: Int = 29) -> Date {
        TestClock.date("2026-09-\(day)T\(time):00+02:00")
    }

    func next(_ events: [CalendarEvent]) -> String? {
        NextMeeting.find(events: events, now: now, calendar: TestClock.paris)?.id
    }

    @Test func picksEarliestUpcoming() {
        let later = CalendarEvent.fixture(id: "later", start: at("15:00"))
        let soon = CalendarEvent.fixture(id: "soon", start: at("11:30"))
        #expect(next([later, soon]) == "soon")
    }

    @Test func skipsOngoingAllDayDeclinedAndTomorrow() {
        let events: [CalendarEvent] = [
            .fixture(id: "ongoing", start: at("10:45")),
            .fixture(id: "startsNow", start: now),
            .fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true),
            .fixture(id: "declined", start: at("12:00"), response: .declined),
            .fixture(id: "tomorrow", start: at("09:00", day: 30)),
        ]
        #expect(next(events) == nil)
        #expect(next(events + [.fixture(id: "tentative", start: at("16:00"), response: .tentative)]) == "tentative")
    }

    @Test func lastMinuteOfTheDayCounts() {
        #expect(next([.fixture(id: "late", start: at("23:59"))]) == "late")
        #expect(next([.fixture(id: "midnight", start: at("00:00", day: 30))]) == nil)
    }

    @Test func ongoingPicksTheOneEndingFirst() {
        let long = CalendarEvent.fixture(id: "long", start: at("10:00"), minutes: 120)
        let short = CalendarEvent.fixture(id: "short", start: at("10:50"), minutes: 20)
        #expect(NextMeeting.ongoing(events: [long, short], now: now)?.id == "short")
    }

    @Test func ongoingSkipsDeclinedAllDayAndFinished() {
        let events: [CalendarEvent] = [
            .fixture(id: "declined", start: at("10:45"), response: .declined),
            .fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true),
            .fixture(id: "done", start: at("10:30"), minutes: 30),
            .fixture(id: "future", start: at("11:01")),
        ]
        #expect(NextMeeting.ongoing(events: events, now: now) == nil)
        #expect(NextMeeting.ongoing(events: [.fixture(id: "starts", start: now)], now: now)?.id == "starts")
    }

    func focus(_ events: [CalendarEvent]) -> String? {
        NextMeeting.focus(events: events, now: now, calendar: TestClock.paris)?.id
    }

    @Test func focusPrefersTheOngoingMeeting() {
        let events: [CalendarEvent] = [
            .fixture(id: "soon", start: at("11:15")),
            .fixture(id: "long", start: at("10:00"), minutes: 120),
            .fixture(id: "short", start: at("10:45"), minutes: 30),
        ]
        #expect(focus(events) == "short")
    }

    @Test func focusFallsBackToTheNextMeeting() {
        let events: [CalendarEvent] = [
            .fixture(id: "done", start: at("10:00"), minutes: 30),
            .fixture(id: "declinedNow", start: at("10:45"), response: .declined),
            .fixture(id: "later", start: at("15:00")),
            .fixture(id: "soon", start: at("11:30")),
        ]
        #expect(focus(events) == "soon")
    }

    @Test func focusIsNilWhenTheDayIsOver() {
        let events: [CalendarEvent] = [
            .fixture(id: "done", start: at("09:00")),
            .fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true),
            .fixture(id: "tomorrow", start: at("09:00", day: 30)),
        ]
        #expect(focus(events) == nil)
    }
}
