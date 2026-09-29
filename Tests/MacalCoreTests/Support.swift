import Foundation
@testable import MacalCore

enum TestClock {
    static let paris: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    /// Parses "2026-09-29T11:00:00+02:00".
    static func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }
}

extension CalendarEvent {
    static func fixture(
        id: String = UUID().uuidString,
        iCalUID: String? = nil,
        account: String = "me@example.com",
        calendarID: String? = nil,
        title: String = "Meeting",
        start: Date,
        minutes: Int = 30,
        allDay: Bool = false,
        response: ResponseStatus = .accepted,
        meeting: MeetingLink? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            iCalUID: iCalUID ?? id,
            accountEmail: account,
            calendarID: calendarID ?? account,
            colorHex: "#4285f4",
            title: title,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: allDay,
            location: nil,
            notes: nil,
            htmlLink: nil,
            organizer: nil,
            attendees: [],
            attachments: [],
            meeting: meeting,
            selfResponse: response
        )
    }
}
