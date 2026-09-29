import Foundation
import Testing
@testable import MacalCore

@Suite struct DayAgendaTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")

    func at(_ time: String, day: Int = 29) -> Date {
        TestClock.date("2026-09-\(day)T\(time):00+02:00")
    }

    @Test func splitsTodayIntoCurrentAndPast() {
        let past = CalendarEvent.fixture(id: "past", start: at("09:00"))
        let ongoing = CalendarEvent.fixture(id: "ongoing", start: at("10:45"))
        let next = CalendarEvent.fixture(id: "next", start: at("14:00"))
        let allDay = CalendarEvent.fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true)
        let tomorrow = CalendarEvent.fixture(id: "tomorrow", start: at("09:30", day: 30))

        let agenda = DayAgenda.build(from: [next, tomorrow, past, allDay, ongoing], now: now, calendar: TestClock.paris)

        #expect(agenda.current.map(\.id) == ["ongoing", "next"])
        #expect(agenda.past.map(\.id) == ["past"])
        #expect(agenda.allDay.map(\.id) == ["off"])
        #expect(agenda.firstTomorrow?.id == "tomorrow")
    }

    @Test func keepsAllDayOnceTimedEventsAreOver() {
        let past = CalendarEvent.fixture(id: "past", start: at("09:00"))
        let off = CalendarEvent.fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true)
        let trip = CalendarEvent.fixture(id: "trip", start: at("00:00", day: 28), minutes: 3 * 1440, allDay: true)
        let agenda = DayAgenda.build(from: [past, off, trip], now: at("22:00"), calendar: TestClock.paris)
        #expect(agenda.current.isEmpty)
        #expect(agenda.allDay.map(\.id) == ["trip", "off"])
    }

    @Test func eventCrossingMidnightFromYesterdayCountsToday() {
        let late = CalendarEvent.fixture(id: "late", start: at("23:30", day: 28), minutes: 60)
        let agenda = DayAgenda.build(from: [late], now: now, calendar: TestClock.paris)
        #expect(agenda.past.map(\.id) == ["late"])
    }

    @Test func relativeLabels() {
        let e = CalendarEvent.fixture(start: at("11:12"), minutes: 30)
        #expect(AgendaFormat.relative(e, now: now) == "in 12 min")
        #expect(AgendaFormat.relative(e, now: at("11:11").addingTimeInterval(30)) == "now")
        #expect(AgendaFormat.relative(e, now: at("11:24")) == "now · 18 min left")
        #expect(AgendaFormat.relative(e, now: at("11:50")) == "ended")
    }

    @Test func durations() {
        #expect(AgendaFormat.duration(59) == "1 min")
        #expect(AgendaFormat.duration(12 * 60) == "12 min")
        #expect(AgendaFormat.duration(65 * 60) == "1 h 5 min")
        #expect(AgendaFormat.duration(120 * 60) == "2 h")
    }

    @Test func timeRange() {
        let e = CalendarEvent.fixture(start: at("09:05"), minutes: 55)
        #expect(AgendaFormat.timeRange(e, calendar: TestClock.paris) == "09:05-10:00")
    }

    @Test func keepsZeroLengthEventAtMidnight() {
        let marker = CalendarEvent.fixture(id: "marker", start: at("00:00"), minutes: 0)
        let agenda = DayAgenda.build(from: [marker], now: now, calendar: TestClock.paris)
        #expect(agenda.past.map(\.id) == ["marker"])
    }

    @Test func zeroLengthEventNowIsCurrent() {
        let reminder = CalendarEvent.fixture(id: "now", start: now, minutes: 0)
        let earlier = CalendarEvent.fixture(id: "earlier", start: at("10:00"), minutes: 0)
        let agenda = DayAgenda.build(from: [reminder, earlier], now: now, calendar: TestClock.paris)
        #expect(agenda.current.map(\.id) == ["now"])
        #expect(agenda.past.map(\.id) == ["earlier"])
    }
}
