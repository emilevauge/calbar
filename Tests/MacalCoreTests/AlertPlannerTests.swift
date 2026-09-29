import Foundation
import Testing
@testable import MacalCore

@Suite struct AlertPlannerTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")
    let policy = AlertPolicy(leadTime: 600, lingerAfterStart: 300)

    func event(inMinutes m: Double, minutes: Int = 30, allDay: Bool = false, response: ResponseStatus = .accepted) -> CalendarEvent {
        .fixture(start: now.addingTimeInterval(m * 60), minutes: minutes, allDay: allDay, response: response)
    }

    func due(_ e: CalendarEvent, dismissed: Set<String> = []) -> Bool {
        !AlertPlanner.due([e], now: now, policy: policy, dismissed: dismissed).isEmpty
    }

    @Test func alertsInsideLeadTime() {
        #expect(!due(event(inMinutes: 11)))
        #expect(due(event(inMinutes: 9)))
        #expect(due(event(inMinutes: 10)))
    }

    @Test func lingersAfterStart() {
        #expect(due(event(inMinutes: -4)))
        #expect(!due(event(inMinutes: -6)))
    }

    @Test func stopsWhenMeetingIsOver() {
        #expect(!due(event(inMinutes: -4, minutes: 3)))
    }

    @Test func skipsDismissedAllDayAndDeclined() {
        let e = event(inMinutes: 5)
        #expect(!due(e, dismissed: [e.occurrenceKey]))
        #expect(!due(event(inMinutes: 5, allDay: true)))
        #expect(!due(event(inMinutes: 5, response: .declined)))
    }

    func badge(_ events: [CalendarEvent], needsAttention: Bool = false) -> MenuBarBadge {
        MenuBarBadge.compute(events: events, now: now, leadTime: 600, calendar: TestClock.paris,
                             needsAttention: needsAttention)
    }

    @Test func badgeCountsMinutesUnderAnHour() {
        let b = badge([event(inMinutes: 25)])
        #expect(b == .countdown(minutes: 25, urgency: .normal))
        #expect(b.text == "25")
        #expect(!b.isProminent)
    }

    @Test func badgeRoundsMinutesUp() {
        #expect(badge([event(inMinutes: 7.5)]) == .countdown(minutes: 8, urgency: .soon))
        #expect(badge([event(inMinutes: 58.2)]).text == "59")
        #expect(badge([event(inMinutes: 59.2)]).text == "1h")
    }

    @Test func badgeSwitchesToWholeHours() {
        #expect(badge([event(inMinutes: 60)]).text == "1h")
        #expect(badge([event(inMinutes: 119)]).text == "1h")
        #expect(badge([event(inMinutes: 135)]).text == "2h")
    }

    @Test func badgeIsProminentInsideLeadTime() {
        let edge = badge([event(inMinutes: 10)])
        #expect(edge == .countdown(minutes: 10, urgency: .soon))
        #expect(edge.isProminent)
        let after = badge([event(inMinutes: 10.5)])
        #expect(after == .countdown(minutes: 11, urgency: .normal))
        #expect(!after.isProminent)
    }

    func badge(inSeconds s: Double, leadTime: TimeInterval = 600) -> MenuBarBadge {
        MenuBarBadge.compute(events: [.fixture(start: now.addingTimeInterval(s))], now: now,
                             leadTime: leadTime, calendar: TestClock.paris, needsAttention: false)
    }

    @Test func badgeUrgencyBoundaries() {
        #expect(badge(inSeconds: 601) == .countdown(minutes: 11, urgency: .normal))
        #expect(badge(inSeconds: 600) == .countdown(minutes: 10, urgency: .soon))
        #expect(badge(inSeconds: 61) == .countdown(minutes: 2, urgency: .soon))
        #expect(badge(inSeconds: 60) == .countdown(minutes: 1, urgency: .imminent))
        #expect(badge(inSeconds: 1) == .countdown(minutes: 1, urgency: .imminent))
    }

    @Test func badgeImminentIsProminentAndShowsOne() {
        let b = badge(inSeconds: 45)
        #expect(b.text == "1")
        #expect(b.isProminent)
        #expect(b.urgency == .imminent)
    }

    @Test func badgeImminentEvenWithShortLeadTime() {
        #expect(badge(inSeconds: 60, leadTime: 30) == .countdown(minutes: 1, urgency: .imminent))
        #expect(badge(inSeconds: 30, leadTime: 30) == .countdown(minutes: 1, urgency: .imminent))
        #expect(badge(inSeconds: 90, leadTime: 30) == .countdown(minutes: 2, urgency: .normal))
    }

    @Test func badgeUrgencyAccessor() {
        #expect(MenuBarBadge.warning.urgency == nil)
        #expect(MenuBarBadge.none.urgency == nil)
        #expect(badge(inSeconds: 3000).urgency == .normal)
        #expect(!badge(inSeconds: 3000).isProminent)
        #expect(badge(inSeconds: 300).isProminent)
    }

    @Test func badgeIgnoresTomorrow() {
        // 11:00 in Paris: 13h after is tomorrow at 00:00.
        let b = badge([event(inMinutes: 13 * 60)])
        #expect(b == .none)
        #expect(b.text == "")
        #expect(!b.isProminent)
        #expect(badge([event(inMinutes: 12 * 60 + 59)]) == .countdown(minutes: 779, urgency: .normal))
    }

    @Test func badgeSkipsOngoingMeeting() {
        let b = badge([event(inMinutes: -10), event(inMinutes: 40)])
        #expect(b == .countdown(minutes: 40, urgency: .normal))
        #expect(badge([event(inMinutes: -10)]) == .none)
    }

    @Test func badgePicksEarliestUpcoming() {
        #expect(badge([event(inMinutes: 90), event(inMinutes: 30)]) == .countdown(minutes: 30, urgency: .normal))
    }

    @Test func badgeIgnoresDeclinedAndAllDay() {
        let events = [event(inMinutes: 5, response: .declined), event(inMinutes: 5, allDay: true)]
        #expect(badge(events) == .none)
    }

    @Test func badgeWarnsWhenAccountNeedsReconnect() {
        let b = badge([event(inMinutes: 5)], needsAttention: true)
        #expect(b == .warning)
        #expect(b.text == "!")
        #expect(b.isProminent)
    }
}
