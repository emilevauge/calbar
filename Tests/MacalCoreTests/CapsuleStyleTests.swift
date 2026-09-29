import Foundation
import Testing
@testable import MacalCore

@Suite struct CapsuleStyleTests {
    let now = TestClock.date("2026-09-29T11:00:00+02:00")
    let link = MeetingLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, provider: .meet)

    func event(inMinutes m: Double) -> CalendarEvent {
        .fixture(title: "Design sync", start: now.addingTimeInterval(m * 60), meeting: link)
    }

    @Test func noPrimaryMeansPlainGlyph() {
        #expect(CapsuleStyle.make(badge: .countdown(minutes: 4, urgency: .soon), primary: nil, now: now) == nil)
        #expect(CapsuleStyle.make(badge: .live(hasLink: false, nextMinutes: 40), primary: nil, now: now) == nil)
    }

    @Test func followsTheBadge() {
        let e = event(inMinutes: 4)
        #expect(CapsuleStyle.make(badge: .countdown(minutes: 4, urgency: .soon), primary: e, now: now) == .soon)
        #expect(CapsuleStyle.make(badge: .countdown(minutes: 1, urgency: .imminent), primary: e, now: now) == .urgent)
        #expect(CapsuleStyle.make(badge: .live(hasLink: true, nextMinutes: 43), primary: e, now: now) == .urgent)
        #expect(CapsuleStyle.make(badge: .live(hasLink: true, nextMinutes: nil), primary: e, now: now) == .urgent)
        #expect(CapsuleStyle.make(badge: .countdown(minutes: 30, urgency: .normal), primary: e, now: now) == .accent)
    }

    @Test func warningUsesTheMeetingTiming() {
        #expect(CapsuleStyle.make(badge: .warning, primary: event(inMinutes: 4), now: now) == .soon)
        #expect(CapsuleStyle.make(badge: .warning, primary: event(inMinutes: 0.5), now: now) == .urgent)
        #expect(CapsuleStyle.make(badge: .warning, primary: event(inMinutes: -2), now: now) == .urgent)
    }

    @Test func headlineIsCapitalized() {
        let e = CalendarEvent.fixture(start: now.addingTimeInterval(240), minutes: 30)
        #expect(AgendaFormat.headline(e, now: now) == "In 4 min")
        #expect(AgendaFormat.headline(e, now: now.addingTimeInterval(200)) == "Now")
        #expect(AgendaFormat.headline(e, now: now.addingTimeInterval(240 + 14 * 60)) == "Now · 16 min left")
    }
}
