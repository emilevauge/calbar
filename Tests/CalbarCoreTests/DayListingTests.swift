import Foundation
import Testing
@testable import CalbarCore

@Suite struct DayWindowTests {
    let paris = TestClock.paris

    @Test func coversOneCalendarDay() {
        let window = DayWindow.interval(for: TestClock.date("2026-09-29T15:20:00+02:00"), calendar: paris)
        #expect(window.start == TestClock.date("2026-09-29T00:00:00+02:00"))
        #expect(window.end == TestClock.date("2026-09-30T00:00:00+02:00"))
    }

    @Test func spansSeveralDays() {
        let window = DayWindow.interval(for: TestClock.date("2026-09-29T15:20:00+02:00"), days: 2, calendar: paris)
        #expect(window.end == TestClock.date("2026-10-01T00:00:00+02:00"))
    }

    @Test func followsDaylightSavingTime() {
        // Paris leaves summer time on October 25, 2026 and enters it on March 29, 2026.
        let autumn = DayWindow.interval(for: TestClock.date("2026-10-25T12:00:00+01:00"), calendar: paris)
        #expect(autumn.duration == 25 * 3600)
        #expect(autumn.start == TestClock.date("2026-10-25T00:00:00+02:00"))
        #expect(autumn.end == TestClock.date("2026-10-26T00:00:00+01:00"))
        let spring = DayWindow.interval(for: TestClock.date("2026-03-29T12:00:00+02:00"), calendar: paris)
        #expect(spring.duration == 23 * 3600)
    }

    @Test func dayOffsets() {
        let today = TestClock.date("2026-09-29T23:59:00+02:00")
        #expect(DayWindow.day(offset: 0, from: today, calendar: paris) == TestClock.date("2026-09-29T00:00:00+02:00"))
        #expect(DayWindow.day(offset: -1, from: today, calendar: paris) == TestClock.date("2026-09-28T00:00:00+02:00"))
        #expect(DayWindow.day(offset: 3, from: today, calendar: paris) == TestClock.date("2026-10-02T00:00:00+02:00"))
        // Across the autumn change the next day still starts at midnight.
        let before = TestClock.date("2026-10-25T10:00:00+02:00")
        #expect(DayWindow.day(offset: 1, from: before, calendar: paris) == TestClock.date("2026-10-26T00:00:00+01:00"))
    }

    @Test func relativeNames() {
        #expect(DayWindow.relativeName(offset: -1) == "Yesterday")
        #expect(DayWindow.relativeName(offset: 0) == "Today")
        #expect(DayWindow.relativeName(offset: 1) == "Tomorrow")
        #expect(DayWindow.relativeName(offset: 2) == nil)
        #expect(DayWindow.relativeName(offset: -5) == nil)
    }
}

@Suite struct DayListingTests {
    let paris = TestClock.paris
    let day = TestClock.date("2026-09-29T00:00:00+02:00")

    func at(_ time: String, day: Int = 29) -> Date {
        TestClock.date("2026-09-\(String(format: "%02d", day))T\(time):00+02:00")
    }

    @Test func listsAllDayThenTimedInOrder() {
        let late = CalendarEvent.fixture(id: "late", start: at("16:00"))
        let early = CalendarEvent.fixture(id: "early", start: at("08:30"))
        let off = CalendarEvent.fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true)
        let other = CalendarEvent.fixture(id: "other", start: at("09:00", day: 30))
        let listing = DayListing.build(events: [late, other, off, early], day: at("12:00"), calendar: paris)
        #expect(listing.allDay.map(\.id) == ["off"])
        #expect(listing.timed.map(\.id) == ["early", "late"])
        #expect(listing.count == 3)
        #expect(!listing.isEmpty)
    }

    @Test func multiDayAllDayEventAppearsOnEachDay() {
        let trip = CalendarEvent.fixture(id: "trip", start: at("00:00", day: 28), minutes: 3 * 1440, allDay: true)
        for d in 28...30 {
            #expect(DayListing.build(events: [trip], day: at("12:00", day: d), calendar: paris).allDay.map(\.id) == ["trip"])
        }
        // The end date is exclusive.
        let after = TestClock.date("2026-10-01T12:00:00+02:00")
        #expect(DayListing.build(events: [trip], day: after, calendar: paris).isEmpty)
        #expect(DayListing.build(events: [trip], day: at("12:00", day: 27), calendar: paris).isEmpty)
    }

    @Test func eventCrossingMidnightAppearsOnBothDays() {
        let late = CalendarEvent.fixture(id: "late", start: at("23:30"), minutes: 60)
        #expect(DayListing.build(events: [late], day: at("12:00"), calendar: paris).timed.map(\.id) == ["late"])
        #expect(DayListing.build(events: [late], day: at("12:00", day: 30), calendar: paris).timed.map(\.id) == ["late"])
        #expect(DayListing.build(events: [late], day: at("12:00", day: 28), calendar: paris).isEmpty)
    }

    @Test func eventEndingAtMidnightStaysOnItsDay() {
        let evening = CalendarEvent.fixture(id: "evening", start: at("23:00"), minutes: 60)
        #expect(DayListing.build(events: [evening], day: at("12:00", day: 30), calendar: paris).isEmpty)
        let marker = CalendarEvent.fixture(id: "marker", start: at("00:00", day: 30), minutes: 0)
        #expect(DayListing.build(events: [marker], day: at("12:00", day: 30), calendar: paris).timed.map(\.id) == ["marker"])
        #expect(DayListing.build(events: [marker], day: at("12:00"), calendar: paris).isEmpty)
    }

    @Test func longDaylightSavingDayKeepsItsLastHour() {
        // October 25, 2026 lasts 25 hours in Paris: 23:30 local is 22:30 UTC.
        let late = CalendarEvent.fixture(id: "late", start: TestClock.date("2026-10-25T23:30:00+01:00"), minutes: 15)
        let day = TestClock.date("2026-10-25T09:00:00+02:00")
        #expect(DayListing.build(events: [late], day: day, calendar: paris).timed.map(\.id) == ["late"])
        let next = TestClock.date("2026-10-26T09:00:00+01:00")
        #expect(DayListing.build(events: [late], day: next, calendar: paris).isEmpty)
    }

    @Test func eventCounts() {
        #expect(AgendaFormat.eventCount(0) == nil)
        #expect(AgendaFormat.eventCount(1) == "1 event")
        #expect(AgendaFormat.eventCount(3) == "3 events")
    }
}

@Suite struct DayCacheTests {
    let t0 = TestClock.date("2026-09-29T10:00:00+02:00")
    let day = TestClock.date("2026-09-28T00:00:00+02:00")

    @Test func unknownDayNeedsFetch() {
        let cache = DayCache<[String]>()
        #expect(cache.entry(for: day) == nil)
        #expect(cache.needsFetch(day, now: t0))
    }

    @Test func loadingDayIsNotFetchedTwice() {
        var cache = DayCache<[String]>()
        cache.begin(day)
        #expect(cache.entry(for: day)?.isLoading == true)
        #expect(!cache.needsFetch(day, now: t0))
    }

    @Test func loadedDayExpiresAfterFiveMinutes() {
        var cache = DayCache<[String]>()
        cache.begin(day)
        cache.finish(day, value: ["a"], at: t0)
        #expect(cache.entry(for: day)?.value == ["a"])
        #expect(cache.entry(for: day)?.isLoading == false)
        #expect(!cache.needsFetch(day, now: t0.addingTimeInterval(299)))
        #expect(cache.needsFetch(day, now: t0.addingTimeInterval(300)))
    }

    @Test func invalidationKeepsValueUntilRefetched() {
        var cache = DayCache<[String]>()
        cache.finish(day, value: ["a"], at: t0)
        cache.invalidate()
        #expect(cache.needsFetch(day, now: t0))
        #expect(cache.entry(for: day)?.value == ["a"])
        cache.begin(day)
        #expect(cache.entry(for: day)?.value == ["a"])
        #expect(!cache.needsFetch(day, now: t0))
    }

    @Test func failureWaitsForRetryOrInvalidation() {
        var cache = DayCache<[String]>()
        cache.begin(day)
        cache.fail(day)
        #expect(cache.entry(for: day)?.failed == true)
        #expect(cache.entry(for: day)?.isLoading == false)
        #expect(!cache.needsFetch(day, now: t0.addingTimeInterval(3600)))
        cache.invalidate()
        #expect(cache.needsFetch(day, now: t0))
        cache.begin(day)
        #expect(cache.entry(for: day)?.failed == false)
    }

    @Test func failedRefetchKeepsPreviousValue() {
        var cache = DayCache<[String]>()
        cache.finish(day, value: ["a"], at: t0)
        cache.invalidate()
        cache.begin(day)
        cache.fail(day)
        #expect(cache.entry(for: day)?.value == ["a"])
        #expect(cache.entry(for: day)?.failed == true)
    }

    @Test func invalidationDuringFetchForcesAnotherFetch() {
        var cache = DayCache<[String]>()
        cache.begin(day)
        cache.invalidate()
        cache.finish(day, value: ["old"], at: t0)
        // The result predates the invalidation: shown, but fetched again.
        #expect(cache.entry(for: day)?.value == ["old"])
        #expect(cache.needsFetch(day, now: t0))
    }

    @Test func mapsValues() {
        var cache = DayCache<[String]>()
        cache.finish(day, value: ["a", "b"], at: t0)
        cache.modifyValues { $0.removeAll { $0 == "a" } }
        #expect(cache.entry(for: day)?.value == ["b"])
    }
}
