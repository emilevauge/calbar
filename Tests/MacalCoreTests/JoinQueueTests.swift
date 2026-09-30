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

    /// Fixture meetings last 30 minutes.
    func progress(startedMinutesAgo m: Double) -> MenuBarBadge.Progress {
        MenuBarBadge.Progress(minutesLeft: Int((30 - m).rounded(.up)), fraction: m / 30)
    }

    @Test func startedMeetingIsLiveWithMinutesLeft() {
        let b = badge([event(inMinutes: -2), event(inMinutes: 40)])
        #expect(b == .live(hasLink: true, meeting: progress(startedMinutesAgo: 2)))
        #expect(b.isProminent)
        #expect(b.text == "28")
        #expect(b.progress == 2.0 / 30)
        #expect(b.urgency == nil)
    }

    @Test func liveFromTheStartSecond() {
        let b = badge([event(inMinutes: 0)])
        #expect(b == .live(hasLink: true, meeting: progress(startedMinutesAgo: 0)))
        #expect(b.text == "30")
    }

    @Test func dismissedShowsTheMeetingOutlined() {
        let started = event(inMinutes: -2)
        let b = badge([started, event(inMinutes: 40)], dismissed: [started.occurrenceKey])
        #expect(b == .inMeeting(progress(startedMinutesAgo: 2)))
        #expect(!b.isProminent)
    }

    @Test func afterLingerShowsMinutesLeftNotTheNextMeeting() {
        let b = badge([event(inMinutes: -6), event(inMinutes: 40)])
        #expect(b == .inMeeting(progress(startedMinutesAgo: 6)))
        #expect(b.text == "24")
        #expect(b.progress == 0.2)
    }

    @Test func nextMeetingAlertBeatsTheOngoingOne() {
        // Back to back: 20 min into a 30 min meeting, the next one is 10 min away.
        #expect(badge([event(inMinutes: -20), event(inMinutes: 10)]) == .countdown(minutes: 10, urgency: .soon))
        #expect(badge([event(inMinutes: -20), event(inMinutes: 11)]) == .inMeeting(progress(startedMinutesAgo: 20)))
    }

    @Test func longMeetingShowsHours() {
        let long = CalendarEvent.fixture(start: now.addingTimeInterval(-600), minutes: 180, meeting: link)
        #expect(badge([long]).text == "2h")
    }

    @Test func declinedIsNotLive() {
        #expect(badge([event(inMinutes: -2, response: .declined), event(inMinutes: 40)])
            == .countdown(minutes: 40, urgency: .normal))
        #expect(badge([event(inMinutes: -10, response: .declined)]) == .none)
    }

    @Test func withoutLinkIsLiveWithoutCamera() {
        let b = badge([event(inMinutes: -2, meeting: false), event(inMinutes: 40)])
        #expect(b == .live(hasLink: false, meeting: progress(startedMinutesAgo: 2)))
        #expect(b.isProminent)
        #expect(badge([event(inMinutes: -6, meeting: false), event(inMinutes: 40)])
            == .inMeeting(progress(startedMinutesAgo: 6)))
    }

    @Test func anyStartedLinkShowsCameraAndTheFirstToEnd() {
        // Both 30 min long: the one that started 3 min ago ends first.
        #expect(badge([event(inMinutes: -3, meeting: false), event(inMinutes: -1)])
            == .live(hasLink: true, meeting: progress(startedMinutesAgo: 3)))
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
