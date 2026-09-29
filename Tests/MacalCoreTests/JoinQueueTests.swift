import Foundation
import Testing
@testable import MacalCore

@Suite struct JoinQueueTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")
    let policy = AlertPolicy(leadTime: 600, lingerAfterStart: 300)
    let link = MeetingLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, provider: .meet)

    func event(_ title: String, inMinutes m: Double, meeting: Bool = true) -> CalendarEvent {
        .fixture(title: title, start: now.addingTimeInterval(m * 60), meeting: meeting ? link : nil)
    }

    func queue(_ events: [CalendarEvent], dismissed: Set<String> = []) -> JoinQueue {
        JoinQueue(events: events, now: now, policy: policy, dismissed: dismissed)
    }

    @Test func emptyWhenNothingIsDue() {
        let q = queue([event("Later", inMinutes: 30)])
        #expect(q.meetings.isEmpty)
        #expect(q.primary == nil)
        #expect(q.extraCount == 0)
        #expect(q.extraLabel == nil)
    }

    @Test func skipsEventsWithoutMeetingLink() {
        let q = queue([event("Lunch", inMinutes: 5, meeting: false)])
        #expect(q.primary == nil)
    }

    @Test func singleMeetingHasNoCount() {
        let q = queue([event("Standup", inMinutes: 5)])
        #expect(q.primary?.title == "Standup")
        #expect(q.extraLabel == nil)
    }

    @Test func earliestFirstWithCount() {
        let q = queue([
            event("Second", inMinutes: 8),
            event("No link", inMinutes: 1, meeting: false),
            event("First", inMinutes: -2),
            event("Too late", inMinutes: 20),
        ])
        #expect(q.meetings.map(\.title) == ["First", "Second"])
        #expect(q.primary?.title == "First")
        #expect(q.extraCount == 1)
        #expect(q.extraLabel == "+1")
    }

    @Test func dismissedMeetingMovesToNext() {
        let first = event("First", inMinutes: 2)
        let second = event("Second", inMinutes: 6)
        let q = queue([first, second], dismissed: [first.occurrenceKey])
        #expect(q.primary?.title == "Second")
        #expect(q.extraLabel == nil)
        #expect(queue([first, second], dismissed: [first.occurrenceKey, second.occurrenceKey]).primary == nil)
    }

    @Test func sameStartIsStable() {
        let a = CalendarEvent.fixture(id: "a", title: "A", start: now.addingTimeInterval(300), meeting: link)
        let b = CalendarEvent.fixture(id: "b", title: "B", start: now.addingTimeInterval(300), meeting: link)
        #expect(queue([b, a]).meetings.map(\.title) == queue([a, b]).meetings.map(\.title))
        #expect(queue([b, a]).extraLabel == "+1")
    }
}

@Suite struct LiveBadgeTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")
    let policy = AlertPolicy(leadTime: 600, lingerAfterStart: 300)
    let link = MeetingLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, provider: .meet)

    func event(inMinutes m: Double, meeting: Bool = true, response: ResponseStatus = .accepted) -> CalendarEvent {
        .fixture(start: now.addingTimeInterval(m * 60), response: response, meeting: meeting ? link : nil)
    }

    func badge(_ events: [CalendarEvent], dismissed: Set<String> = [], needsAttention: Bool = false) -> MenuBarBadge {
        let due = AlertPlanner.due(events, now: now, policy: policy, dismissed: dismissed)
        return MenuBarBadge.compute(events: events, now: now, leadTime: policy.leadTime,
                                    calendar: TestClock.paris, needsAttention: needsAttention,
                                    due: due)
    }

    @Test func startedMeetingIsLive() {
        let b = badge([event(inMinutes: -2), event(inMinutes: 40)])
        #expect(b == .live(hasLink: true, nextMinutes: 40))
        #expect(b.isProminent)
        #expect(b.text == "40")
        #expect(b.urgency == nil)
    }

    @Test func liveShowsHoursToNextMeeting() {
        #expect(badge([event(inMinutes: -2), event(inMinutes: 135)]).text == "2h")
    }

    @Test func liveWithoutNextMeetingIsEmpty() {
        let b = badge([event(inMinutes: -2)])
        #expect(b == .live(hasLink: true, nextMinutes: nil))
        #expect(b.text == "")
    }

    @Test func liveFromTheStartSecond() {
        #expect(badge([event(inMinutes: 0)]) == .live(hasLink: true, nextMinutes: nil))
    }

    @Test func dismissedGoesBackToCountdown() {
        let started = event(inMinutes: -2)
        #expect(badge([started, event(inMinutes: 40)], dismissed: [started.occurrenceKey])
            == .countdown(minutes: 40, urgency: .normal))
    }

    @Test func afterLingerGoesBackToCountdown() {
        #expect(badge([event(inMinutes: -6), event(inMinutes: 40)]) == .countdown(minutes: 40, urgency: .normal))
    }

    @Test func declinedIsNotLive() {
        #expect(badge([event(inMinutes: -2, response: .declined), event(inMinutes: 40)])
            == .countdown(minutes: 40, urgency: .normal))
    }

    @Test func withoutLinkIsLiveWithoutCamera() {
        let b = badge([event(inMinutes: -2, meeting: false), event(inMinutes: 40)])
        #expect(b == .live(hasLink: false, nextMinutes: 40))
        #expect(b.isProminent)
        #expect(badge([event(inMinutes: -6, meeting: false), event(inMinutes: 40)])
            == .countdown(minutes: 40, urgency: .normal))
    }

    @Test func anyStartedLinkShowsCamera() {
        #expect(badge([event(inMinutes: -3, meeting: false), event(inMinutes: -1)]) == .live(hasLink: true, nextMinutes: nil))
    }

    @Test func allDayIsNotLive() {
        let allDay = CalendarEvent.fixture(start: now.addingTimeInterval(-120), allDay: true, meeting: link)
        #expect(badge([allDay]) == .none)
    }

    @Test func upcomingDueMeetingKeepsCountdown() {
        #expect(badge([event(inMinutes: 5)]) == .countdown(minutes: 5, urgency: .soon))
        #expect(badge([event(inMinutes: 0.5)]) == .countdown(minutes: 1, urgency: .imminent))
    }

    @Test func warningHasPriority() {
        #expect(badge([event(inMinutes: -2)], needsAttention: true) == .warning)
    }
}
