import Foundation
import Testing
@testable import CalbarCore

@Suite struct RefreshMergeTests {
    let ten = TestClock.date("2026-09-29T10:00:00+02:00")

    func event(_ id: String, _ account: String, _ calendar: String) -> CalendarEvent {
        .fixture(id: id, account: account, calendarID: calendar, start: ten)
    }

    @Test func keepsNothingWhenEverythingSucceeded() {
        let previous = [event("a", "me@x", "cal1")]
        #expect(RefreshMerge.kept(previous: previous, failedAccounts: [], failedCalendars: []).isEmpty)
    }

    @Test func keepsEveryEventOfAFailedAccount() {
        let previous = [event("a", "me@x", "cal1"), event("b", "me@x", "cal2"), event("c", "pro@y", "cal3")]
        let kept = RefreshMerge.kept(previous: previous, failedAccounts: ["me@x"], failedCalendars: [])
        #expect(kept.map(\.id) == ["a", "b"])
    }

    @Test func keepsOnlyTheFailedCalendarOfAnAccount() {
        let previous = [event("a", "me@x", "cal1"), event("b", "me@x", "cal2")]
        let failed: Set<CalendarKey> = [CalendarKey(email: "me@x", calendarID: "cal2")]
        let kept = RefreshMerge.kept(previous: previous, failedAccounts: [], failedCalendars: failed)
        #expect(kept.map(\.id) == ["b"])
    }

    @Test func calendarKeyIsScopedToTheAccount() {
        // The same calendar shared with two accounts has one ID for both.
        let previous = [event("a", "me@x", "shared"), event("b", "pro@y", "shared")]
        let failed: Set<CalendarKey> = [CalendarKey(email: "pro@y", calendarID: "shared")]
        let kept = RefreshMerge.kept(previous: previous, failedAccounts: [], failedCalendars: failed)
        #expect(kept.map(\.id) == ["b"])
    }

    @Test func mergeAppendsKeptEventsToCollected() {
        let previous = [event("old", "me@x", "cal1"), event("stale", "pro@y", "cal2")]
        let collected = [event("new", "pro@y", "cal2")]
        let merged = RefreshMerge.merge(collected: collected, previous: previous,
                                        failedAccounts: ["me@x"], failedCalendars: [])
        #expect(merged.map(\.id) == ["new", "old"])
    }
}
