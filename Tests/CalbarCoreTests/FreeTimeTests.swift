import Foundation
import Testing
@testable import CalbarCore

@Suite struct FreeTimeTests {
    let at = { (t: String) in TestClock.date("2026-09-29T\(t):00+02:00") }

    @Test func gapBetweenEvents() {
        let a = CalendarEvent.fixture(id: "a", start: at("10:00"), minutes: 30)
        let b = CalendarEvent.fixture(id: "b", start: at("12:00"), minutes: 30)
        #expect(FreeTime.gaps([a, b]) == ["b": TimeInterval(90 * 60)])
    }

    @Test func shortGapsAreSkipped() {
        let a = CalendarEvent.fixture(id: "a", start: at("10:00"), minutes: 30)
        let b = CalendarEvent.fixture(id: "b", start: at("10:59"), minutes: 30)
        let c = CalendarEvent.fixture(id: "c", start: at("12:00"), minutes: 30)
        #expect(FreeTime.gaps([a, b, c]) == ["c": TimeInterval(31 * 60)])
    }

    @Test func nestedEventOpensNoGap() {
        let long = CalendarEvent.fixture(id: "long", start: at("09:00"), minutes: 240)
        let inside = CalendarEvent.fixture(id: "in", start: at("10:00"), minutes: 30)
        let after = CalendarEvent.fixture(id: "after", start: at("14:00"), minutes: 30)
        #expect(FreeTime.gaps([long, inside, after]) == ["after": TimeInterval(60 * 60)])
    }

    @Test func emptyAndSingle() {
        #expect(FreeTime.gaps([]).isEmpty)
        #expect(FreeTime.gaps([.fixture(start: at("10:00"))]).isEmpty)
    }
}
