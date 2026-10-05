import Foundation

/// Other people's availability, from Google's `freebusy.query`: when each
/// one is busy, never what they do. Calendars Google will not share (an
/// outside domain, a private calendar) come back as `unknown`.
public enum FreeBusy {
    public enum Availability: Equatable, Sendable {
        case busy([DateInterval])
        case unknown
    }

    /// What a query gives: each calendar's availability, and the members
    /// of the groups among the emails (Google expands them), each in
    /// `availability` too.
    public struct Result: Equatable, Sendable {
        public var availability: [String: Availability] = [:]
        /// Lowercased group email to its members' lowercased emails.
        public var groups: [String: [String]] = [:]

        public init(availability: [String: Availability] = [:], groups: [String: [String]] = [:]) {
            self.availability = availability
            self.groups = groups
        }
    }

    /// Google answers at most 50 calendars per query.
    static let batch = 50

    /// The `freebusy.query` body for `emails` over `from..<to`; groups
    /// expanded to their members, up to Google's limits.
    static func body(emails: [String], from: Date, to: Date) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "timeMin": GoogleDate.rfc3339(from),
            "timeMax": GoogleDate.rfc3339(to),
            "items": emails.map { ["id": $0] },
            "groupExpansionMax": 100,
            "calendarExpansionMax": 50,
        ], options: [.sortedKeys])
    }

    /// The groups of the answer, by lowercased email: their members.
    static func parseGroups(_ data: Data) throws -> [String: [String]] {
        struct Answer: Decodable {
            struct Group: Decodable { let calendars: [String]? }
            let groups: [String: Group]?
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        var result: [String: [String]] = [:]
        for (email, group) in answer.groups ?? [:] {
            let members = (group.calendars ?? []).map { $0.lowercased() }
            if !members.isEmpty { result[email.lowercased()] = members }
        }
        return result
    }

    /// Each calendar of the answer, by lowercased email.
    static func parse(_ data: Data) throws -> [String: Availability] {
        struct Answer: Decodable {
            struct Entry: Decodable {
                struct Span: Decodable { let start: String; let end: String }
                struct Failure: Decodable { let reason: String? }
                let busy: [Span]?
                let errors: [Failure]?
            }
            let calendars: [String: Entry]
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        var result: [String: Availability] = [:]
        for (email, entry) in answer.calendars {
            if let errors = entry.errors, !errors.isEmpty {
                result[email.lowercased()] = .unknown
                continue
            }
            let spans = (entry.busy ?? []).compactMap { span -> DateInterval? in
                guard let start = GoogleDate.dateTime(span.start), let end = GoogleDate.dateTime(span.end),
                      end > start else { return nil }
                return DateInterval(start: start, end: end)
            }
            result[email.lowercased()] = .busy(spans)
        }
        return result
    }

    /// `busy` without `own`: the meeting being moved keeps its guests busy
    /// in Google, but its time is not taken by anything else.
    public static func removing(_ own: DateInterval, from busy: [DateInterval]) -> [DateInterval] {
        busy.flatMap { span -> [DateInterval] in
            guard span.start < own.end, own.start < span.end else { return [span] }
            var parts: [DateInterval] = []
            if span.start < own.start { parts.append(DateInterval(start: span.start, end: own.start)) }
            if own.end < span.end { parts.append(DateInterval(start: own.end, end: span.end)) }
            return parts
        }
    }

    /// Overlapping or touching intervals joined, sorted.
    public static func union(_ spans: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, span.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// The times of `days`, between `startHour` and `endHour` and not
    /// before `notBefore`, when nobody in `busy` is busy, kept when at
    /// least `duration` long: where the meeting fits for everyone.
    public static func commonFree(busy: [[DateInterval]], days: [Date], startHour: Int, endHour: Int,
                                  duration: TimeInterval, notBefore: Date, calendar: Calendar) -> [DateInterval] {
        let taken = union(busy.flatMap { $0 })
        var result: [DateInterval] = []
        for day in days {
            let midnight = calendar.startOfDay(for: day)
            guard let open = calendar.date(byAdding: .hour, value: startHour, to: midnight),
                  let close = calendar.date(byAdding: .hour, value: endHour, to: midnight) else { continue }
            var cursor = max(open, notBefore)
            for span in taken where span.end > cursor && span.start < close {
                if span.start > cursor { result.append(DateInterval(start: cursor, end: span.start)) }
                cursor = max(cursor, span.end)
            }
            if cursor < close { result.append(DateInterval(start: cursor, end: close)) }
        }
        return result.filter { $0.duration >= duration }
    }

    /// Busy times by email of the people shown (`shown`, lowercased) among
    /// `people`: a group stands for its members, each shown with it, or
    /// alone when picked; `own` (the event moved or edited) left out.
    public static func busy(people: [String], shown: Set<String>, result: Result,
                            removing own: DateInterval?) -> [String: [DateInterval]] {
        var emails: [String] = []
        for person in people {
            if let members = result.groups[person] {
                emails += members.filter { shown.contains(person) || shown.contains($0) }
            } else if shown.contains(person) {
                emails.append(person)
            }
        }
        var busy: [String: [DateInterval]] = [:]
        for email in emails {
            if case .busy(let spans) = result.availability[email] {
                busy[email] = own.map { removing($0, from: spans) } ?? spans
            }
        }
        return busy
    }

    /// The people shown after a click on `key`, a person, a group or a
    /// group's member: alone when everyone was shown, else in or out. A
    /// member taken out of a shown group leaves the rest of the group.
    public static func toggle(_ key: String, shown: Set<String>, everyone: Set<String>,
                              groups: [String: [String]]) -> Set<String> {
        if shown == everyone { return [key] }
        var next = shown
        if next.contains(key) {
            next.remove(key)
        } else if let group = groups.first(where: { next.contains($0.key) && $0.value.contains(key) }) {
            next.remove(group.key)
            next.formUnion(group.value.filter { $0 != key })
        } else {
            next.insert(key)
        }
        return next.isEmpty ? everyone : next
    }

    /// Who in `busy` is busy at some point of `slot`.
    public static func conflicts(_ slot: DateInterval, busy: [String: [DateInterval]]) -> [String] {
        busy.filter { _, spans in spans.contains { $0.start < slot.end && slot.start < $0.end } }
            .map(\.key).sorted()
    }
}

extension CalendarAPI {
    /// Availability of `emails` over `from..<to`, as seen by the account
    /// of `token`, in batches of 50; groups come with their members.
    public func freeBusy(token: String, emails: [String], from: Date, to: Date) async throws -> FreeBusy.Result {
        var result = FreeBusy.Result()
        var rest = emails
        while !rest.isEmpty {
            let chunk = Array(rest.prefix(FreeBusy.batch))
            rest.removeFirst(chunk.count)
            let data = try await post("/freeBusy", body: try FreeBusy.body(emails: chunk, from: from, to: to), token: token)
            result.availability.merge(try FreeBusy.parse(data)) { _, new in new }
            result.groups.merge(try FreeBusy.parseGroups(data)) { _, new in new }
        }
        // A group is not a calendar: its own entry, an error, says nothing.
        for group in result.groups.keys { result.availability[group] = nil }
        return result
    }
}
