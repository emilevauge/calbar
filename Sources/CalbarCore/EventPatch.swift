import Foundation

/// The `events.patch` body that turns `original` into `draft`, the
/// editor's state: only the fields the user changed, so a description in
/// HTML or guests' answers survive an edit of the title.
public struct EventPatch {
    public let body: Data
    /// Guests before or after: Google emails them the change.
    public let notify: Bool
    /// A Meet link is requested: needs `conferenceDataVersion=1`.
    public let addsConference: Bool

    /// - Parameters:
    ///   - current: the event being patched as Google returns it, the
    ///     occurrence or, for `series`, the recurring event itself.
    ///   - notesText: the description as the editor showed it, plain text.
    ///   - series: the change goes to every occurrence: times move by
    ///     the same amount from the series' own start.
    public init(original: CalendarEvent, draft: NewEvent, notesText: String, current: Data,
                series: Bool, calendar: Calendar = .current) throws {
        let raw = (try JSONSerialization.jsonObject(with: current)) as? [String: Any] ?? [:]
        var json: [String: Any] = [:]

        if draft.summary != original.title { json["summary"] = draft.summary }

        if draft.start != original.start || draft.end != original.end {
            struct Times: Decodable { let start: GoogleEvent.Time? }
            if series, let masterStart = try? JSONDecoder().decode(Times.self, from: current).start
                .flatMap({ GoogleDate.parse($0, calendar: calendar) })?.date {
                let start = masterStart.addingTimeInterval(draft.start.timeIntervalSince(original.start))
                let end = start.addingTimeInterval(draft.end.timeIntervalSince(draft.start))
                var timed = draft
                timed.timeZone = (raw["start"] as? [String: Any])?["timeZone"] as? String ?? draft.timeZone
                json["start"] = timed.time(start, calendar: calendar)
                json["end"] = timed.time(end, calendar: calendar)
            } else {
                json["start"] = draft.time(draft.start, calendar: calendar)
                json["end"] = draft.time(draft.end, calendar: calendar)
            }
        }

        let trim = { (s: String?) in (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var place = trim(draft.location)
        if let zoom = draft.zoom, place.isEmpty { place = zoom.joinURL.absoluteString }
        if place != trim(original.location) { json["location"] = place }

        let text = trim(draft.notes)
        if text != trim(notesText) || draft.zoom != nil {
            // Unchanged notes keep their HTML under the Zoom invitation.
            let kept = text == trim(notesText) ? trim(original.notes) : text
            if let zoom = draft.zoom {
                json["description"] = kept.isEmpty ? zoom.description : zoom.description + "\n\n" + kept
            } else {
                json["description"] = kept
            }
        }

        let before = Set(original.attendees.filter { !$0.isSelf }.map { $0.person.email.lowercased() })
        let after = Set(draft.guests.map { $0.lowercased() })
        if before != after {
            // Entries kept as Google has them, with their answers; the
            // user and meeting rooms, which the editor does not list, too.
            let existing = raw["attendees"] as? [[String: Any]] ?? []
            var list = existing.filter { a in
                a["self"] as? Bool == true || a["resource"] as? Bool == true
                    || after.contains((a["email"] as? String ?? "").lowercased())
            }
            let present = Set(list.compactMap { ($0["email"] as? String)?.lowercased() })
            list += draft.guests.filter { !present.contains($0.lowercased()) }.map { ["email": $0] }
            json["attendees"] = list
        }

        addsConference = draft.addMeet && original.meeting == nil
        if addsConference {
            json["conferenceData"] = ["createRequest": [
                "requestId": UUID().uuidString,
                "conferenceSolutionKey": ["type": "hangoutsMeet"],
            ]]
        }

        if !draft.recurrence.isEmpty && !original.isRecurring { json["recurrence"] = draft.recurrence }

        notify = !before.isEmpty || !after.isEmpty
        body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    /// Nothing changed: no request to send.
    public var isEmpty: Bool { body == Data("{}".utf8) }
}
