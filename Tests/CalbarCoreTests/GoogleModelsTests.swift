import Foundation
import Testing
@testable import CalbarCore

@Suite struct GoogleModelsTests {
    let source = CalendarInfo(id: "alice@example.com", name: "Alice", colorHex: "#9fe1e7", isPrimary: true, enabled: true)

    func event(_ json: String) throws -> CalendarEvent? {
        let g = try JSONDecoder().decode(GoogleEvent.self, from: Data(json.utf8))
        return CalendarEvent(google: g, accountEmail: "alice@example.com", source: source, calendar: TestClock.paris)
    }

    @Test func mapsFullEvent() throws {
        let json = #"""
        {
          "id": "abc123_20260929T083000Z",
          "iCalUID": "abc123@google.com",
          "status": "confirmed",
          "summary": "Traefik x Acme call",
          "description": "Agenda: <a href=\"https://docs.google.com/document/d/xyz\">notes</a>",
          "location": "Everest room",
          "htmlLink": "https://www.google.com/calendar/event?eid=YWJj",
          "start": {"dateTime": "2026-09-29T10:30:00+02:00", "timeZone": "Europe/Paris"},
          "end": {"dateTime": "2026-09-29T11:00:00+02:00", "timeZone": "Europe/Paris"},
          "organizer": {"email": "bob@acme.com", "displayName": "Bob"},
          "attendees": [
            {"email": "bob@acme.com", "displayName": "Bob", "organizer": true, "responseStatus": "accepted"},
            {"email": "alice@example.com", "self": true, "responseStatus": "tentative"},
            {"email": "everest@resource.calendar.google.com", "resource": true, "responseStatus": "accepted"}
          ],
          "conferenceData": {"entryPoints": [
            {"entryPointType": "phone", "uri": "tel:+33-1-23-45-67-89"},
            {"entryPointType": "video", "uri": "https://us02web.zoom.us/j/85012345678?pwd=abc"}
          ]},
          "attachments": [{
            "fileUrl": "https://docs.google.com/document/d/xyz",
            "title": "Notes",
            "mimeType": "application/vnd.google-apps.document",
            "iconLink": "https://drive-thirdparty.googleusercontent.com/16/type/application/vnd.google-apps.document"
          }],
          "eventType": "default"
        }
        """#
        let e = try #require(try event(json))
        #expect(e.id == "alice@example.com/alice@example.com/abc123_20260929T083000Z")
        #expect(e.iCalUID == "abc123@google.com")
        #expect(e.title == "Traefik x Acme call")
        #expect(e.start == TestClock.date("2026-09-29T08:30:00Z"))
        #expect(e.end == TestClock.date("2026-09-29T09:00:00Z"))
        #expect(!e.isAllDay)
        #expect(e.colorHex == "#9fe1e7")
        #expect(e.organizer == Person(email: "bob@acme.com", name: "Bob"))
        #expect(e.attendees.count == 2)
        #expect(e.attendees[0].isOrganizer)
        #expect(e.selfResponse == .tentative)
        #expect(e.meeting?.provider == .zoom)
        #expect(e.attachments.first?.title == "Notes")
        #expect(e.location == "Everest room")
    }

    @Test func mapsAllDayEventInLocalTime() throws {
        let json = #"{"id": "d1", "summary": "Vacation", "start": {"date": "2026-09-29"}, "end": {"date": "2026-09-30"}}"#
        let e = try #require(try event(json))
        #expect(e.isAllDay)
        #expect(e.start == TestClock.date("2026-09-29T00:00:00+02:00"))
        #expect(e.end == TestClock.date("2026-09-30T00:00:00+02:00"))
        #expect(e.selfResponse == .accepted)
        #expect(e.iCalUID == "d1")
    }

    @Test func untitledEventGetsPlaceholder() throws {
        let json = #"{"id": "u", "start": {"dateTime": "2026-09-29T10:00:00Z"}, "end": {"dateTime": "2026-09-29T10:30:00Z"}}"#
        #expect(try event(json)?.title == "(No title)")
    }

    @Test func skipsCancelledAndWorkingLocation() throws {
        let cancelled = #"{"id": "c", "status": "cancelled", "start": {"dateTime": "2026-09-29T10:00:00Z"}, "end": {"dateTime": "2026-09-29T10:30:00Z"}}"#
        let office = #"{"id": "w", "eventType": "workingLocation", "start": {"date": "2026-09-29"}, "end": {"date": "2026-09-30"}}"#
        #expect(try event(cancelled) == nil)
        #expect(try event(office) == nil)
    }

    @Test func parsesFractionalSeconds() {
        #expect(GoogleDate.dateTime("2026-09-29T10:00:00.000Z") == TestClock.date("2026-09-29T10:00:00Z"))
    }

    @Test func mapsCalendarListEntry() throws {
        let json = ##"{"items": [{"id": "team@group.calendar.google.com", "summary": "Team", "summaryOverride": "Équipe", "backgroundColor": "#16a765", "selected": true}]}"##
        let list = try JSONDecoder().decode(GoogleCalendarList.self, from: Data(json.utf8))
        let info = CalendarInfo(google: list.items[0])
        #expect(info == CalendarInfo(id: "team@group.calendar.google.com", name: "Équipe", colorHex: "#16a765", isPrimary: false, enabled: false))
    }

    @Test func unselectedSecondaryCalendarStartsDisabled() throws {
        let json = #"{"items": [{"id": "x", "summary": "Anniversaires"}]}"#
        let list = try JSONDecoder().decode(GoogleCalendarList.self, from: Data(json.utf8))
        #expect(CalendarInfo(google: list.items[0]).enabled == false)
    }

    @Test func onlyPrimaryCalendarStartsEnabled() throws {
        let json = #"{"items": [{"id": "me@x.com", "primary": true, "selected": true}, {"id": "team", "selected": true}, {"id": "holidays"}]}"#
        let list = try JSONDecoder().decode(GoogleCalendarList.self, from: Data(json.utf8))
        #expect(list.items.map { CalendarInfo(google: $0).enabled } == [true, false, false])
    }

    @Test func cancelledInstanceWithoutTimesDecodes() throws {
        let json = #"{"items": [{"id": "x", "status": "cancelled"}, {"id": "ok", "start": {"dateTime": "2026-09-29T10:00:00Z"}, "end": {"dateTime": "2026-09-29T10:30:00Z"}}]}"#
        let list = try JSONDecoder().decode(GoogleEventList.self, from: Data(json.utf8))
        let events = list.items.compactMap {
            CalendarEvent(google: $0, accountEmail: "alice@example.com", source: source, calendar: TestClock.paris)
        }
        #expect(events.map(\.id) == ["alice@example.com/alice@example.com/ok"])
    }

    @Test func whitespaceTitleGetsPlaceholder() throws {
        let json = #"{"id": "u", "summary": "  \n ", "start": {"dateTime": "2026-09-29T10:00:00Z"}, "end": {"dateTime": "2026-09-29T10:30:00Z"}}"#
        #expect(try event(json)?.title == "(No title)")
    }

    @Test func rejectsImpossibleDays() {
        #expect(GoogleDate.day("2026-13-45", calendar: TestClock.paris) == nil)
        #expect(GoogleDate.day("2026-02-30", calendar: TestClock.paris) == nil)
        #expect(GoogleDate.day("2026-09-29", calendar: TestClock.paris) == TestClock.date("2026-09-29T00:00:00+02:00"))
    }

    @Test func formatsRFC3339InUTC() {
        #expect(GoogleDate.rfc3339(TestClock.date("2026-09-29T00:00:00+02:00")) == "2026-09-28T22:00:00Z")
    }
}
