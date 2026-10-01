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
}
