import Foundation
import Testing
@testable import CalbarCore

@Suite struct RecurrenceTests {
    let cal = TestClock.paris
    /// 2026-09-29 is the fifth Tuesday of September.
    let fifthTuesday = TestClock.date("2026-09-29T10:00:00+02:00")
    let firstThursday = TestClock.date("2026-10-01T10:00:00+02:00")

    @Test func rules() {
        #expect(RepeatRule.none.rrule(start: firstThursday, calendar: cal) == nil)
        #expect(RepeatRule.daily.rrule(start: firstThursday, calendar: cal) == "RRULE:FREQ=DAILY")
        #expect(RepeatRule.weekly.rrule(start: firstThursday, calendar: cal) == "RRULE:FREQ=WEEKLY;BYDAY=TH")
        #expect(RepeatRule.biweekly.rrule(start: firstThursday, calendar: cal) == "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TH")
        #expect(RepeatRule.monthlyByWeekday.rrule(start: firstThursday, calendar: cal) == "RRULE:FREQ=MONTHLY;BYDAY=1TH")
        #expect(RepeatRule.monthlyByWeekday.rrule(start: fifthTuesday, calendar: cal) == "RRULE:FREQ=MONTHLY;BYDAY=-1TU")
        #expect(RepeatRule.monthlyByDay.rrule(start: firstThursday, calendar: cal) == "RRULE:FREQ=MONTHLY;BYMONTHDAY=1")
    }

    @Test func labels() {
        #expect(RepeatRule.weekly.label(start: firstThursday, calendar: cal) == "Weekly on Thursday")
        #expect(RepeatRule.monthlyByWeekday.label(start: firstThursday, calendar: cal) == "Monthly on the first Thursday")
        #expect(RepeatRule.monthlyByWeekday.label(start: fifthTuesday, calendar: cal) == "Monthly on the last Tuesday")
        #expect(RepeatRule.yearly.label(start: firstThursday, calendar: cal) == "Annually on October 1")
    }

    @Test func truncateReplacesCountAndUntil() {
        let rules = ["RRULE:FREQ=WEEKLY;COUNT=10;BYDAY=TH", "EXDATE;TZID=Europe/Paris:20261008T100000"]
        #expect(Recurrence.truncate(rules, before: firstThursday, allDay: false, calendar: cal) == [
            "RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261001T075959Z",
            "EXDATE;TZID=Europe/Paris:20261008T100000",
        ])
        let day = cal.startOfDay(for: firstThursday)
        #expect(Recurrence.truncate(["RRULE:FREQ=DAILY;UNTIL=20270101"], before: day, allDay: true, calendar: cal)
                == ["RRULE:FREQ=DAILY;UNTIL=20260930"])
    }

    func occurrence(attendees: [Attendee] = [], notes: String? = nil, rooms: [Person] = []) -> CalendarEvent {
        CalendarEvent(
            id: "me@x.com/me@x.com/s_20261001T080000Z", iCalUID: "s@google.com", accountEmail: "me@x.com",
            calendarID: "me@x.com", colorHex: "#000", title: "Sync", start: firstThursday,
            end: firstThursday.addingTimeInterval(1800), isAllDay: false, location: "Room", notes: notes,
            htmlLink: nil, organizer: nil, attendees: attendees, attachments: [], meeting: nil,
            selfResponse: .accepted, recurringEventID: "s", originalStart: firstThursday, rooms: rooms)
    }

    func draft(_ e: CalendarEvent) -> NewEvent {
        var d = NewEvent(title: e.title, start: e.start, end: e.end, calendarID: e.calendarID, addMeet: false,
                         location: e.location ?? "", notes: "", guests: e.attendees.filter { !$0.isSelf }.map(\.person.email),
                         timeZone: "Europe/Paris")
        d.rooms = e.rooms.map(\.email)
        return d
    }

    func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func patchSendsOnlyChanges() throws {
        let e = occurrence(notes: "<b>Agenda</b>")
        var d = draft(e)
        d.notes = "Agenda"
        #expect(try EventPatch(original: e, draft: d, notesText: "Agenda", current: Data("{}".utf8), series: false,
                               calendar: cal).isEmpty)
        d.title = "Weekly sync"
        let patch = try EventPatch(original: e, draft: d, notesText: "Agenda", current: Data("{}".utf8), series: false,
                                   calendar: cal)
        #expect(try json(patch.body).keys.sorted() == ["summary"])
        #expect(!patch.notify)
    }

    @Test func patchKeepsAnswersAndAddsGuests() throws {
        let me = Attendee(person: Person(email: "me@x.com", name: nil), response: .accepted, isOrganizer: true, isSelf: true, isOptional: false)
        let ann = Attendee(person: Person(email: "ann@x.com", name: nil), response: .accepted, isOrganizer: false, isSelf: false, isOptional: false)
        let bob = Attendee(person: Person(email: "bob@x.com", name: nil), response: .declined, isOrganizer: false, isSelf: false, isOptional: false)
        let e = occurrence(attendees: [me, ann, bob], rooms: [Person(email: "room@resource.calendar.google.com", name: "Room")])
        var d = draft(e)
        d.guests = ["ann@x.com", "cy@x.com"]
        let current = #"{"attendees": [{"email": "me@x.com", "self": true, "organizer": true}, {"email": "ann@x.com", "responseStatus": "accepted"}, {"email": "bob@x.com", "responseStatus": "declined"}, {"email": "room@resource.calendar.google.com", "resource": true}]}"#
        let patch = try EventPatch(original: e, draft: d, notesText: "", current: Data(current.utf8), series: false, calendar: cal)
        let list = try #require(try json(patch.body)["attendees"] as? [[String: Any]])
        #expect(list.compactMap { $0["email"] as? String } == ["me@x.com", "ann@x.com", "room@resource.calendar.google.com", "cy@x.com"])
        #expect(list[1]["responseStatus"] as? String == "accepted")
        #expect(patch.notify)
    }

    @Test func seriesTimesMoveFromTheSeriesStart() throws {
        let e = occurrence()
        var d = draft(e)
        d.start = e.start.addingTimeInterval(3600)
        d.end = d.start.addingTimeInterval(3600)
        let current = #"{"start": {"dateTime": "2026-09-03T10:00:00+02:00", "timeZone": "Europe/Paris"}, "end": {"dateTime": "2026-09-03T10:30:00+02:00"}}"#
        let body = try json(EventPatch(original: e, draft: d, notesText: "", current: Data(current.utf8), series: true, calendar: cal).body)
        #expect((body["start"] as? [String: String])?["dateTime"] == "2026-09-03T09:00:00Z")
        #expect((body["end"] as? [String: String])?["dateTime"] == "2026-09-03T10:00:00Z")
    }

    @Test func deleteFollowingEndsTheSeries() async throws {
        let master = #"{"id": "s", "start": {"dateTime": "2026-09-03T10:00:00+02:00"}, "end": {"dateTime": "2026-09-03T10:30:00+02:00"}, "recurrence": ["RRULE:FREQ=WEEKLY;BYDAY=TH"]}"#
        let http = StubHTTP([(200, master), (200, "{}")])
        try await CalendarAPI(http: http).delete(token: "t", event: occurrence(), scope: .following, calendar: cal)
        #expect(http.requests.map(\.httpMethod) == ["GET", "PATCH"])
        #expect(http.requests[1].url?.path.hasSuffix("/events/s") == true)
        let body = try json(try #require(http.requests[1].httpBody))
        #expect(body["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261001T075959Z"])
    }

    @Test func deleteFollowingFromTheFirstDeletesAll() async throws {
        let master = #"{"id": "s", "start": {"dateTime": "2026-10-01T10:00:00+02:00"}, "end": {"dateTime": "2026-10-01T10:30:00+02:00"}, "recurrence": ["RRULE:FREQ=DAILY"]}"#
        let http = StubHTTP([(200, master), (204, "")])
        try await CalendarAPI(http: http).delete(token: "t", event: occurrence(), scope: .following, calendar: cal)
        #expect(http.requests.map(\.httpMethod) == ["GET", "DELETE"])
        #expect(http.requests[1].url?.path.hasSuffix("/events/s") == true)
    }

    @Test func deleteScopes() async throws {
        let http = StubHTTP([(204, ""), (204, "")])
        let api = CalendarAPI(http: http)
        try await api.delete(token: "t", event: occurrence(), scope: .this, calendar: cal)
        try await api.delete(token: "t", event: occurrence(), scope: .all, calendar: cal)
        #expect(http.requests[0].url?.path.hasSuffix("/events/s_20261001T080000Z") == true)
        #expect(http.requests[1].url?.path.hasSuffix("/events/s") == true)
    }

    @Test func newEventRepeatsAndAllDay() throws {
        var e = NewEvent(title: "Gym", start: firstThursday, end: firstThursday.addingTimeInterval(3600),
                         calendarID: "me", addMeet: false, timeZone: "Europe/Paris")
        e.recurrence = ["RRULE:FREQ=WEEKLY;BYDAY=TH"]
        #expect(try json(e.body())["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;BYDAY=TH"])
        e.isAllDay = true
        e.start = cal.startOfDay(for: firstThursday)
        e.end = e.start.addingTimeInterval(86_400)
        // `time` uses the current calendar; this test only checks the shape.
        #expect((try json(e.body())["start"] as? [String: String])?.keys.sorted() == ["date"])
    }

    @Test func readsSeriesFields() throws {
        let item = #"{"id": "s_1", "recurringEventId": "s", "originalStartTime": {"dateTime": "2026-10-01T08:00:00Z"}, "start": {"dateTime": "2026-10-01T09:00:00Z"}, "end": {"dateTime": "2026-10-01T09:30:00Z"}}"#
        let g = try JSONDecoder().decode(GoogleEvent.self, from: Data(item.utf8))
        let e = try #require(CalendarEvent(google: g, accountEmail: "me@x.com",
                                           source: CalendarInfo(id: "me@x.com", name: "Me", colorHex: "#000", isPrimary: true, enabled: true),
                                           calendar: cal))
        #expect(e.recurringEventID == "s")
        #expect(e.originalStart == TestClock.date("2026-10-01T08:00:00Z"))
    }

    @Test func updateFollowingSplitsTheSeries() async throws {
        let master = #"{"id": "s", "iCalUID": "s@google.com", "etag": "x", "summary": "Sync", "location": "Room", "start": {"dateTime": "2026-09-03T10:00:00+02:00", "timeZone": "Europe/Paris"}, "end": {"dateTime": "2026-09-03T10:30:00+02:00", "timeZone": "Europe/Paris"}, "recurrence": ["RRULE:FREQ=WEEKLY;COUNT=20;BYDAY=TH"], "attendees": [{"email": "me@x.com", "self": true, "organizer": true}, {"email": "ann@x.com", "responseStatus": "accepted"}], "conferenceData": {"conferenceId": "abc", "entryPoints": [{"entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"}]}}"#
        let http = StubHTTP([(200, master), (200, "{}"), (200, "{}")])
        let ann = Attendee(person: Person(email: "ann@x.com", name: nil), response: .accepted, isOrganizer: false, isSelf: false, isOptional: false)
        let e = occurrence(attendees: [ann])
        var d = draft(e)
        d.title = "Weekly sync"
        d.start = e.start.addingTimeInterval(3600)
        d.end = e.end.addingTimeInterval(3600)
        try await CalendarAPI(http: http).update(token: "t", original: e, draft: d, notesText: "", scope: .following, calendar: cal)
        #expect(http.requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
        let new = try json(try #require(http.requests[1].httpBody))
        #expect(new["summary"] as? String == "Weekly sync")
        #expect(new["id"] == nil && new["iCalUID"] == nil)
        #expect((new["start"] as? [String: String])?["dateTime"] == "2026-10-01T09:00:00Z")
        #expect((new["start"] as? [String: String])?["timeZone"] == "Europe/Paris")
        #expect(new["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;BYDAY=TH"])
        #expect((new["attendees"] as? [[String: Any]])?.count == 2)
        #expect(http.requests[1].url?.query?.contains("conferenceDataVersion=1") == true)
        let cut = try json(try #require(http.requests[2].httpBody))
        #expect(cut["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261001T075959Z"])
    }

    @Test func roomsAddedAndRemoved() throws {
        let room = Person(email: "a@resource.calendar.google.com", name: "Rome")
        let e = occurrence(rooms: [room])
        var d = draft(e)
        d.rooms = ["b@resource.calendar.google.com"]
        let current = #"{"attendees": [{"email": "me@x.com", "self": true}, {"email": "a@resource.calendar.google.com", "resource": true, "responseStatus": "accepted"}]}"#
        let body = try json(EventPatch(original: e, draft: d, notesText: "", current: Data(current.utf8), series: false, calendar: cal).body)
        let list = try #require(body["attendees"] as? [[String: Any]])
        #expect(list.compactMap { $0["email"] as? String } == ["me@x.com", "b@resource.calendar.google.com"])
        #expect(list.last?["resource"] as? Bool == true)
        var n = NewEvent(title: "x", start: firstThursday, end: firstThursday.addingTimeInterval(1800), calendarID: "me", addMeet: false)
        n.rooms = ["b@resource.calendar.google.com"]
        let created = try json(n.body())
        #expect((created["attendees"] as? [[String: Any]])?.first?["resource"] as? Bool == true)
    }
}
