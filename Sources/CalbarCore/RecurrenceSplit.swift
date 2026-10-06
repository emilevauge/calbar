import Foundation

/// The second half of a series split at an occurrence ("this and
/// following"): the series as Google has it, with the editor's changes,
/// starting at the occurrence's new times, its rules without `COUNT`,
/// which counted from the first occurrence. Guests, their answers, the
/// video link and the rest come along.
public struct RecurrenceSplit {
    /// The `events.insert` body of the new series.
    public let newSeries: Data
    public let notify: Bool
    /// A video link, kept or requested: needs `conferenceDataVersion=1`.
    public let hasConference: Bool

    public init(master: Data, original: CalendarEvent, draft: NewEvent, notesText: String,
                calendar: Calendar = .current) throws {
        var json = (try JSONSerialization.jsonObject(with: master)) as? [String: Any] ?? [:]
        let patch = try EventPatch(original: original, draft: draft, notesText: notesText, current: master,
                                   series: false, calendar: calendar)
        let changes = (try JSONSerialization.jsonObject(with: patch.body)) as? [String: Any] ?? [:]
        // Read only, or the old series' own.
        for key in ["id", "iCalUID", "etag", "htmlLink", "created", "updated", "sequence", "recurringEventId",
                    "originalStartTime", "creator", "organizer", "kind", "status", "hangoutLink"] {
            json[key] = nil
        }
        for (key, value) in changes where key != "recurrence" { json[key] = value }
        var timed = draft
        timed.timeZone = (json["start"] as? [String: Any])?["timeZone"] as? String ?? draft.timeZone
        json["start"] = timed.time(draft.start, calendar: calendar)
        json["end"] = timed.time(draft.end, calendar: calendar)
        json["recurrence"] = ((json["recurrence"] as? [String]) ?? []).map(Self.withoutCount)
        if var conference = json["conferenceData"] as? [String: Any], changes["conferenceData"] == nil {
            // The same link: a create request would be the old series'.
            conference["createRequest"] = nil
            json["conferenceData"] = conference
        }
        newSeries = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        notify = patch.notify
        hasConference = json["conferenceData"] != nil
    }

    static func withoutCount(_ line: String) -> String {
        guard line.uppercased().hasPrefix("RRULE:") else { return line }
        let parts = line.dropFirst("RRULE:".count).split(separator: ";")
            .filter { $0.split(separator: "=").first?.uppercased() != "COUNT" }
        return "RRULE:" + parts.joined(separator: ";")
    }
}
