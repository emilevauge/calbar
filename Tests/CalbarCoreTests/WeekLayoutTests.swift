import Foundation
import Testing
@testable import CalbarCore

@Suite struct WeekLayoutTests {
    let calendar: Calendar = {
        var c = TestClock.paris
        c.firstWeekday = 2
        return c
    }()
    let at = { (t: String) in TestClock.date("2026-09-30T\(t):00+02:00") }

    @Test func weekStartsOnTheFirstWeekday() {
        let days = WeekLayout.days(containing: at("15:00"), calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first == TestClock.date("2026-09-28T00:00:00+02:00"))
        #expect(days.last == TestClock.date("2026-10-04T00:00:00+02:00"))
        var sunday = calendar
        sunday.firstWeekday = 1
        #expect(WeekLayout.days(containing: at("15:00"), calendar: sunday).first
            == TestClock.date("2026-09-27T00:00:00+02:00"))
    }

    @Test func titleAcrossMonthsAndYears() {
        let now = at("10:00")
        let days = WeekLayout.days(containing: now, calendar: calendar)
        #expect(WeekLayout.title(days, now: now, calendar: calendar) == "Sep 28 - Oct 4")
        let later = WeekLayout.days(containing: TestClock.date("2026-10-07T10:00:00+02:00"), calendar: calendar)
        #expect(WeekLayout.title(later, now: now, calendar: calendar) == "Oct 5 - 11")
        let next = WeekLayout.days(containing: TestClock.date("2027-01-13T10:00:00+01:00"), calendar: calendar)
        #expect(WeekLayout.title(next, now: now, calendar: calendar) == "Jan 11 - 17, 2027")
    }

    @Test func separateEventsTakeTheFullWidth() {
        let a = CalendarEvent.fixture(id: "a", start: at("09:00"), minutes: 60)
        let b = CalendarEvent.fixture(id: "b", start: at("11:00"), minutes: 30)
        let p = WeekLayout.place([b, a], day: at("12:00"), calendar: calendar)
        #expect(p.map(\.event.id) == ["a", "b"])
        #expect(p.map(\.lanes) == [1, 1])
        #expect(p[0].startMinute == 9 * 60 && p[0].endMinute == 10 * 60)
    }

    @Test func overlappingEventsShareLanes() {
        let a = CalendarEvent.fixture(id: "a", start: at("09:00"), minutes: 120)
        let b = CalendarEvent.fixture(id: "b", start: at("09:30"), minutes: 30)
        let c = CalendarEvent.fixture(id: "c", start: at("10:15"), minutes: 30)
        let p = WeekLayout.place([a, b, c], day: at("12:00"), calendar: calendar)
        let lanes = Dictionary(uniqueKeysWithValues: p.map { ($0.event.id, $0.lane) })
        #expect(lanes == ["a": 0, "b": 1, "c": 1])
        #expect(p.allSatisfy { $0.lanes == 2 })
    }

    @Test func backToBackIsNotAnOverlap() {
        let a = CalendarEvent.fixture(id: "a", start: at("09:00"), minutes: 60)
        let b = CalendarEvent.fixture(id: "b", start: at("10:00"), minutes: 60)
        #expect(WeekLayout.place([a, b], day: at("12:00"), calendar: calendar).map(\.lanes) == [1, 1])
    }

    @Test func clipsToTheDayAndSkipsAllDay() {
        let night = CalendarEvent.fixture(id: "n", start: TestClock.date("2026-09-29T23:00:00+02:00"), minutes: 120)
        let allDay = CalendarEvent.fixture(id: "d", start: TestClock.date("2026-09-30T00:00:00+02:00"), minutes: 1440, allDay: true)
        let p = WeekLayout.place([night, allDay], day: at("12:00"), calendar: calendar)
        #expect(p.map(\.event.id) == ["n"])
        #expect(p[0].startMinute == 0 && p[0].endMinute == 60)
    }

    @Test func eventsOfADayOrMoreLeaveTheGrid() {
        let trip = CalendarEvent.fixture(id: "t", start: TestClock.date("2026-09-29T08:00:00+02:00"), minutes: 2 * 1440)
        let night = CalendarEvent.fixture(id: "n", start: TestClock.date("2026-09-29T22:00:00+02:00"), minutes: 4 * 60)
        #expect(trip.spansDays)
        #expect(!night.spansDays)
        #expect(!CalendarEvent.fixture(start: at("09:00"), minutes: 1440, allDay: true).spansDays)
        #expect(WeekLayout.place([trip, night], day: at("12:00"), calendar: calendar).map(\.event.id) == ["n"])
    }

    @Test func multiDayEventsAreOneBar() {
        let days = WeekLayout.days(containing: at("12:00"), calendar: calendar)
        let trip = CalendarEvent.fixture(id: "trip", start: TestClock.date("2026-09-28T08:00:00+02:00"), minutes: 3 * 1440)
        let off = CalendarEvent.fixture(id: "off", start: TestClock.date("2026-09-29T00:00:00+02:00"), minutes: 1440, allDay: true)
        let weekend = CalendarEvent.fixture(id: "we", start: TestClock.date("2026-10-03T00:00:00+02:00"), minutes: 2 * 1440, allDay: true)
        let bars = WeekLayout.bars([off, weekend, trip], days: days, calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: bars.map { ($0.event.id, $0) })
        #expect(byID["trip"].map { ($0.first, $0.last, $0.row) } ?? (0, 0, 0) == (0, 3, 0))
        #expect(byID["off"].map { ($0.first, $0.last, $0.row) } ?? (0, 0, 0) == (1, 1, 1))
        #expect(byID["we"].map { ($0.first, $0.last, $0.row) } ?? (0, 0, 0) == (5, 6, 0))
        #expect(bars.count == 3)
    }

    @Test func barsClipToTheWeekAndCountHidden() {
        let days = WeekLayout.days(containing: at("12:00"), calendar: calendar)
        let long = CalendarEvent.fixture(id: "l", start: TestClock.date("2026-09-20T00:00:00+02:00"), minutes: 20 * 1440, allDay: true)
        let bars = WeekLayout.bars([long], days: days, calendar: calendar)
        #expect(bars.first.map { ($0.first, $0.last, $0.continuesBefore, $0.continuesAfter) } ?? (0, 0, false, false)
            == (0, 6, true, true))
        let stack = (0..<4).map { CalendarEvent.fixture(id: "s\($0)", start: TestClock.date("2026-09-30T00:00:00+02:00"), minutes: 1440, allDay: true) }
        let stacked = WeekLayout.bars(stack, days: days, calendar: calendar)
        #expect(WeekLayout.hidden(stacked, rows: 2, days: 7) == [0, 0, 2, 0, 0, 0, 0])
    }

    @Test func shownWeekdaysOnly() {
        let workdays = WeekLayout.weekdays("23456")
        #expect(workdays == [2, 3, 4, 5, 6])
        let days = WeekLayout.days(containing: at("12:00"), calendar: calendar, shown: workdays)
        #expect(days.count == 5)
        #expect(days.first == TestClock.date("2026-09-28T00:00:00+02:00"))
        #expect(days.last == TestClock.date("2026-10-02T00:00:00+02:00"))
        #expect(WeekLayout.days(containing: at("12:00"), calendar: calendar, shown: []).count == 7)
        #expect(WeekLayout.weekdays("9x1") == [1])
    }

    @Test func barsOverShownDaysOnly() {
        let days = WeekLayout.days(containing: at("12:00"), calendar: calendar, shown: WeekLayout.weekdays("23456"))
        let weekend = CalendarEvent.fixture(id: "we", start: TestClock.date("2026-10-03T00:00:00+02:00"), minutes: 2 * 1440, allDay: true)
        let late = CalendarEvent.fixture(id: "late", start: TestClock.date("2026-10-01T00:00:00+02:00"), minutes: 3 * 1440, allDay: true)
        let bars = WeekLayout.bars([weekend, late], days: days, calendar: calendar)
        #expect(bars.map(\.event.id) == ["late"])
        #expect(bars.first.map { ($0.first, $0.last, $0.continuesAfter) } ?? (0, 0, false) == (3, 4, true))
    }
}
