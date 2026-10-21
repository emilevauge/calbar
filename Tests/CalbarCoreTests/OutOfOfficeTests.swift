import Foundation
import Testing
@testable import CalbarCore

@Suite struct OutOfOfficeTests {
    let cal = TestClock.paris

    func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func bodyIsAnAbsenceWithTimesOnly() throws {
        let start = TestClock.date("2026-10-26T00:00:00+01:00")
        var e = NewEvent(title: "Holidays", start: start, end: start.addingTimeInterval(3 * 86_400),
                         calendarID: "me@x.com", addMeet: true, location: "Lyon", notes: "Back on Thursday",
                         guests: ["ann@x.com"], timeZone: "Europe/Paris")
        e.isAllDay = true
        e.outOfOffice = OutOfOffice(decline: .all, message: " Away ")
        let j = try json(e.body())
        #expect(j["eventType"] as? String == "outOfOffice")
        let props = try #require(j["outOfOfficeProperties"] as? [String: String])
        #expect(props == ["autoDeclineMode": "declineAllConflictingInvitations", "declineMessage": "Away"])
        // Google refuses an all-day absence: whole days as times.
        #expect((j["start"] as? [String: String])?["dateTime"] == GoogleDate.rfc3339(start))
        #expect((j["start"] as? [String: String])?["date"] == nil)
        #expect(j["attendees"] == nil && j["location"] == nil && j["description"] == nil && j["conferenceData"] == nil)
    }

    @Test func noMessageWhenNothingIsDeclined() {
        #expect(OutOfOffice(decline: .none, message: "Away").properties as? [String: String]
                == ["autoDeclineMode": "declineNone"])
    }

    @Test func parsesAnAbsence() throws {
        let source = CalendarInfo(id: "me@x.com", name: "Me", colorHex: "#000000", isPrimary: true, enabled: true)
        let raw = #"""
        {"id": "ooo1", "summary": "Out of office", "eventType": "outOfOffice",
         "start": {"dateTime": "2026-10-26T14:00:00+01:00"}, "end": {"dateTime": "2026-10-26T16:00:00+01:00"},
         "outOfOfficeProperties": {"autoDeclineMode": "declineOnlyNewConflictingInvitations", "declineMessage": "Away"}}
        """#
        let g = try JSONDecoder().decode(GoogleEvent.self, from: Data(raw.utf8))
        let e = try #require(CalendarEvent(google: g, accountEmail: "me@x.com", source: source, calendar: cal))
        #expect(e.outOfOffice == OutOfOffice(decline: .newOnly, message: "Away"))
        // Never a meeting to count down to or alert about.
        #expect(NextMeeting.ongoing(events: [e], now: e.start.addingTimeInterval(60)) == nil)
        #expect(NextMeeting.find(events: [e], now: e.start.addingTimeInterval(-600), calendar: cal) == nil)
    }

    @Test func patchChangesWhatIsDeclined() throws {
        let start = TestClock.date("2026-10-26T00:00:00+01:00")
        let original = CalendarEvent(
            id: "me@x.com/me@x.com/ooo1", iCalUID: "ooo1", accountEmail: "me@x.com", calendarID: "me@x.com",
            colorHex: "#000000", title: "Out of office", start: start, end: start.addingTimeInterval(86_400),
            isAllDay: false, location: nil, notes: nil, htmlLink: nil, organizer: nil, attendees: [], attachments: [],
            meeting: nil, selfResponse: .accepted, outOfOffice: OutOfOffice(decline: .newOnly, message: "Away"))
        var d = NewEvent(title: "Out of office", start: original.start, end: original.end, calendarID: "me@x.com",
                         addMeet: false, timeZone: "Europe/Paris")
        // The editor shows it as a whole day: no switch to a date.
        d.isAllDay = true
        d.outOfOffice = OutOfOffice(decline: .all, message: "Away")
        let patch = try EventPatch(original: original, draft: d, notesText: "", current: Data("{}".utf8),
                                   series: false, calendar: cal)
        let body = try json(patch.body)
        #expect(body.keys.sorted() == ["outOfOfficeProperties"])
    }
}
