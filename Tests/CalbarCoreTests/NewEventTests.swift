import Foundation
import Testing
@testable import CalbarCore

@Suite struct NewEventTests {
    let start = TestClock.date("2026-10-01T14:15:00+02:00")

    func json(_ e: NewEvent) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: e.body(requestID: "r1")) as! [String: Any]
    }

    @Test func bodyHasTitleAndTimes() throws {
        let e = NewEvent(title: "  Review ", start: start, end: start.addingTimeInterval(1800),
                         calendarID: "me@example.com", addMeet: false, timeZone: "Europe/Paris")
        let j = try json(e)
        #expect(j["summary"] as? String == "Review")
        #expect((j["start"] as? [String: String])?["timeZone"] == "Europe/Paris")
        #expect((j["start"] as? [String: String])?["dateTime"] == GoogleDate.rfc3339(start))
        #expect((j["end"] as? [String: String])?["dateTime"] == GoogleDate.rfc3339(start.addingTimeInterval(1800)))
        #expect(j["conferenceData"] == nil)
    }

    @Test func meetRequest() throws {
        let e = NewEvent(title: "", start: start, end: start.addingTimeInterval(1800),
                         calendarID: "c", addMeet: true)
        let j = try json(e)
        #expect(j["summary"] as? String == "(No title)")
        let request = (j["conferenceData"] as? [String: Any])?["createRequest"] as? [String: Any]
        #expect(request?["requestId"] as? String == "r1")
        #expect((request?["conferenceSolutionKey"] as? [String: String])?["type"] == "hangoutsMeet")
    }

    @Test func slotSnapsToTheQuarter() {
        #expect(NewEvent.slot(minute: 14 * 60 + 22.7) == 14 * 60 + 15)
        #expect(NewEvent.slot(minute: 9 * 60) == 9 * 60)
        #expect(NewEvent.slot(minute: -3) == 0)
        #expect(NewEvent.slot(minute: 23 * 60 + 50) == 23 * 60 + 30)
    }

    @Test func writableCalendars() {
        #expect(CalendarInfo(id: "p", name: "p", colorHex: "#000", isPrimary: true, enabled: true).isWritable)
        #expect(!CalendarInfo(id: "o", name: "o", colorHex: "#000", isPrimary: false, enabled: true).isWritable)
        #expect(CalendarInfo(id: "w", name: "w", colorHex: "#000", isPrimary: false, enabled: true, canWrite: true).isWritable)
        #expect(!CalendarInfo(id: "r", name: "r", colorHex: "#000", isPrimary: true, enabled: true, canWrite: false).isWritable)
    }
}
