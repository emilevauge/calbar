import Foundation
import Testing
@testable import MacalCore

@Suite struct DayStartPolicyTests {
    let calendar = TestClock.paris
    let morning = TestClock.date("2026-09-29T08:30:00+02:00")

    func shouldOpen(last: String?, now: Date, meetings: Int = 2, enabled: Bool = true) -> Bool {
        DayStartPolicy.shouldOpen(lastOpenedDay: last, now: now, calendar: calendar,
                                  remainingMeetings: meetings, enabled: enabled)
    }

    @Test func dayKeyUsesTheCalendarTimeZone() {
        // 23:30 UTC on the 28th is already the 29th in Paris.
        let lateUTC = TestClock.date("2026-09-28T23:30:00Z")
        #expect(DayStartPolicy.dayKey(for: lateUTC, calendar: calendar) == "2026-09-29")
        #expect(DayStartPolicy.dayKey(for: TestClock.date("2026-01-05T10:00:00+01:00"), calendar: calendar) == "2026-01-05")
    }

    @Test func opensOnANewDayWithMeetings() {
        #expect(shouldOpen(last: nil, now: morning))
        #expect(shouldOpen(last: "2026-09-28", now: morning))
    }

    @Test func doesNotOpenTwiceTheSameDay() {
        #expect(!shouldOpen(last: "2026-09-29", now: morning))
        #expect(!shouldOpen(last: "2026-09-29", now: TestClock.date("2026-09-29T23:59:00+02:00")))
    }

    @Test func doesNotOpenWithoutMeetings() {
        #expect(!shouldOpen(last: "2026-09-28", now: morning, meetings: 0))
    }

    @Test func doesNotOpenWhenDisabled() {
        #expect(!shouldOpen(last: "2026-09-28", now: morning, enabled: false))
    }

    @Test func opensAgainAfterMidnight() {
        let beforeMidnight = TestClock.date("2026-09-29T23:59:00+02:00")
        let afterMidnight = TestClock.date("2026-09-30T00:01:00+02:00")
        let key = DayStartPolicy.dayKey(for: beforeMidnight, calendar: calendar)
        #expect(!shouldOpen(last: key, now: beforeMidnight))
        #expect(shouldOpen(last: key, now: afterMidnight))
    }

    @Test func dayKeyIsStableAcrossDaylightSavingChanges() {
        // Paris leaves summer time on 2026-10-25 at 03:00 (a 25-hour day)
        // and enters it on 2026-03-29 at 02:00 (a 23-hour day).
        let autumnStart = TestClock.date("2026-10-25T00:30:00+02:00")
        let autumnEnd = TestClock.date("2026-10-25T23:30:00+01:00")
        #expect(DayStartPolicy.dayKey(for: autumnStart, calendar: calendar) == "2026-10-25")
        #expect(DayStartPolicy.dayKey(for: autumnEnd, calendar: calendar) == "2026-10-25")
        #expect(!shouldOpen(last: "2026-10-25", now: autumnEnd))
        #expect(shouldOpen(last: "2026-10-25", now: TestClock.date("2026-10-26T00:10:00+01:00")))

        let springStart = TestClock.date("2026-03-29T00:30:00+01:00")
        let springEnd = TestClock.date("2026-03-29T23:30:00+02:00")
        #expect(DayStartPolicy.dayKey(for: springStart, calendar: calendar) == "2026-03-29")
        #expect(DayStartPolicy.dayKey(for: springEnd, calendar: calendar) == "2026-03-29")
    }

    @Test func remainingMeetingsSkipsDeclinedAndAllDayAndPast() {
        let now = TestClock.date("2026-09-29T11:00:00+02:00")
        let at = { (t: String) in TestClock.date("2026-09-29T\(t):00+02:00") }
        let events = [
            CalendarEvent.fixture(id: "past", start: at("09:00")),
            CalendarEvent.fixture(id: "off", start: at("00:00"), minutes: 1440, allDay: true),
            CalendarEvent.fixture(id: "declined", start: at("14:00"), response: .declined),
            CalendarEvent.fixture(id: "next", start: at("15:00")),
            CalendarEvent.fixture(id: "maybe", start: at("16:00"), response: .tentative),
        ]
        let agenda = DayAgenda.build(from: events, now: now, calendar: calendar)
        #expect(DayStartPolicy.remainingMeetings(in: agenda) == 2)
    }
}
