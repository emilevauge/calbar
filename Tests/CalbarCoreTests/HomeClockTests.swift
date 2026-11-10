import Foundation
import Testing
@testable import CalbarCore

struct HomeClockTests {
    let paris = TimeZone(identifier: "Europe/Paris")!
    // 2026-11-10 14:00 UTC.
    let date = Date(timeIntervalSince1970: 1_794_319_200)

    @Test func atHomeOrSameTimeIsNotAway() {
        #expect(HomeClock.away(home: "Europe/Paris", current: paris, at: date) == nil)
        #expect(HomeClock.away(home: "Europe/Paris", current: TimeZone(identifier: "Europe/Berlin")!, at: date) == nil)
        #expect(HomeClock.away(home: "", current: paris, at: date) == nil)
    }

    @Test func travelShowsHomeTime() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let home = HomeClock.away(home: "Europe/Paris", current: newYork, at: date)
        #expect(home == paris)
        #expect(HomeClock.label(date, in: paris) == "15:00")
        #expect(HomeClock.label(date, in: TimeZone(identifier: "Asia/Kolkata")!) == "19:30")
    }

    @Test func names() {
        #expect(HomeClock.name(paris, at: date) == "Paris (GMT+1)")
        #expect(HomeClock.name(TimeZone(identifier: "Asia/Kolkata")!, at: date) == "Kolkata (GMT+5:30)")
        #expect(HomeClock.name(TimeZone(identifier: "America/New_York")!, at: date) == "New York (GMT-5)")
    }
}
