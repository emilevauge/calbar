import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }
}

public enum APIError: Error, Equatable {
    /// Access token expired or revoked: refresh it and retry once.
    case unauthorized
    /// The access token lacks the scope the request needs: the account
    /// was signed in before Calbar asked for it and must reconnect.
    case insufficientScope
    case http(status: Int, body: String)
    case invalidResponse

    /// Error for a non-2xx answer of the Calendar API.
    static func from(status: Int, body: Data) -> APIError {
        if status == 401 { return .unauthorized }
        if status == 403 && isScopeError(body) { return .insufficientScope }
        return .http(status: status, body: String(decoding: body, as: UTF8.self))
    }

    /// Google reports a missing scope with the legacy reason
    /// `insufficientPermissions` in `errors` and, in newer answers,
    /// `ACCESS_TOKEN_SCOPE_INSUFFICIENT` in `details`.
    private static func isScopeError(_ body: Data) -> Bool {
        struct Envelope: Decodable {
            struct Body: Decodable {
                struct Reason: Decodable { let reason: String? }
                let errors: [Reason]?
                let details: [Reason]?
            }
            let error: Body
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return false }
        let reasons = (envelope.error.errors ?? []) + (envelope.error.details ?? [])
        return reasons.contains { $0.reason == "insufficientPermissions" || $0.reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT" }
    }
}

/// Client for the Calendar API endpoints Calbar needs: the calendar list
/// and events to read, one event to answer an invitation.
public struct CalendarAPI: Sendable {
    private static let base = "https://www.googleapis.com/calendar/v3"
    private let http: HTTPClient

    public init(http: HTTPClient = URLSession.shared) {
        self.http = http
    }

    public func calendars(token: String) async throws -> [CalendarInfo] {
        var result: [CalendarInfo] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GoogleCalendarList = try await get("/users/me/calendarList", query: query, token: token)
            result += page.items.map(CalendarInfo.init(google:))
            pageToken = Self.next(page.nextPageToken, after: pageToken)
        } while pageToken != nil
        return result
    }

    /// Every occurrence overlapping `from..<to`, recurring meetings expanded.
    public func events(
        token: String,
        source: CalendarInfo,
        accountEmail: String,
        from: Date,
        to: Date,
        calendar: Calendar
    ) async throws -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        var pageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: GoogleDate.rfc3339(from)),
                URLQueryItem(name: "timeMax", value: GoogleDate.rfc3339(to)),
                URLQueryItem(name: "maxResults", value: "250"),
            ]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GoogleEventList = try await get(
                "/calendars/\(FormEncoding.escape(source.id))/events", query: query, token: token
            )
            result += page.items.compactMap {
                CalendarEvent(google: $0, accountEmail: accountEmail, source: source, calendar: calendar)
            }
            pageToken = Self.next(page.nextPageToken, after: pageToken)
        } while pageToken != nil
        return result
    }

    /// Answers an invitation for one occurrence: reads the event, changes
    /// the user's `responseStatus` in its attendee list and sends the list
    /// back. `sendUpdates=all` lets the organizer know, as the Google
    /// Calendar web UI does.
    public func respond(token: String, calendarID: String, eventID: String, response: ResponseStatus) async throws {
        let path = "/calendars/\(FormEncoding.escape(calendarID))/events/\(FormEncoding.escape(eventID))"
        let event = try await send("GET", path, query: [], body: nil, token: token)
        let body = try RSVPPatch.body(event: event, response: response)
        _ = try await send("PATCH", path, query: [URLQueryItem(name: "sendUpdates", value: "all")], body: body, token: token)
    }

    /// Proposes `start..<end` to the organizer of an invitation: the
    /// user's answer with a note (`RSVPPatch.proposal`), the organizer
    /// told by Google.
    public func propose(token: String, calendarID: String, eventID: String, start: Date, end: Date) async throws {
        let path = "/calendars/\(FormEncoding.escape(calendarID))/events/\(FormEncoding.escape(eventID))"
        let event = try await send("GET", path, query: [], body: nil, token: token)
        let body = try RSVPPatch.proposal(event: event, start: start, end: end)
        _ = try await send("PATCH", path, query: [URLQueryItem(name: "sendUpdates", value: "all")], body: body, token: token)
    }

    /// Adds an event, with a Google Meet link when `NewEvent.addMeet`.
    /// `sendUpdates=all` emails the invitation to the guests.
    public func insert(token: String, event: NewEvent) async throws {
        var query: [URLQueryItem] = []
        if !event.guests.isEmpty { query.append(URLQueryItem(name: "sendUpdates", value: "all")) }
        if event.addMeet { query.append(URLQueryItem(name: "conferenceDataVersion", value: "1")) }
        _ = try await send("POST", "/calendars/\(FormEncoding.escape(event.calendarID))/events",
                           query: query, body: try event.body(), token: token)
    }

    /// Deletes one event, or one occurrence of a recurring one (its id is
    /// the occurrence's). Guests get Google's cancellation when `notify`.
    public func delete(token: String, calendarID: String, eventID: String, notify: Bool) async throws {
        let path = "/calendars/\(FormEncoding.escape(calendarID))/events/\(FormEncoding.escape(eventID))"
        _ = try await send("DELETE", path, query: [URLQueryItem(name: "sendUpdates", value: notify ? "all" : "none")],
                           body: nil, token: token)
    }

    /// Deletes `event`, its whole series, or the series from it on: the
    /// series then ends just before it (`Recurrence.truncate`), or goes
    /// entirely when `event` is its first occurrence.
    public func delete(token: String, event: CalendarEvent, scope: RecurrenceScope,
                       calendar: Calendar = .current) async throws {
        let notify = event.attendees.contains { !$0.isSelf }
        guard let series = event.recurringEventID, scope != .this else {
            return try await delete(token: token, calendarID: event.calendarID, eventID: event.googleEventID, notify: notify)
        }
        if scope == .all {
            return try await delete(token: token, calendarID: event.calendarID, eventID: series, notify: notify)
        }
        let path = eventPath(event.calendarID, series)
        let master = try JSONDecoder().decode(GoogleEvent.self, from: await send("GET", path, query: [], body: nil, token: token))
        let cut = event.originalStart ?? event.start
        let first = master.start.flatMap { GoogleDate.parse($0, calendar: calendar) }?.date
        if let first, cut <= first {
            return try await delete(token: token, calendarID: event.calendarID, eventID: series, notify: notify)
        }
        let rules = Recurrence.truncate(master.recurrence ?? [], before: cut, allDay: event.isAllDay, calendar: calendar)
        let body = try JSONSerialization.data(withJSONObject: ["recurrence": rules])
        _ = try await send("PATCH", path, query: [URLQueryItem(name: "sendUpdates", value: notify ? "all" : "none")],
                           body: body, token: token)
    }

    /// Saves the editor's `draft` over `original`, or over its whole
    /// series for `.all`: reads the event, then patches what changed.
    public func update(token: String, original: CalendarEvent, draft: NewEvent, notesText: String,
                       scope: RecurrenceScope, calendar: Calendar = .current) async throws {
        if scope == .following, let series = original.recurringEventID {
            return try await updateFollowing(token: token, original: original, series: series, draft: draft,
                                             notesText: notesText, calendar: calendar)
        }
        let series = scope == .all ? original.recurringEventID : nil
        let path = eventPath(original.calendarID, series ?? original.googleEventID)
        let current = try await send("GET", path, query: [], body: nil, token: token)
        let patch = try EventPatch(original: original, draft: draft, notesText: notesText, current: current,
                                   series: series != nil, calendar: calendar)
        guard !patch.isEmpty else { return }
        var query = [URLQueryItem(name: "sendUpdates", value: patch.notify ? "all" : "none")]
        if patch.addsConference { query.append(URLQueryItem(name: "conferenceDataVersion", value: "1")) }
        _ = try await send("PATCH", path, query: query, body: patch.body, token: token)
    }

    /// "This and following": the series ends before the occurrence and a
    /// copy of it, with the changes, starts at the occurrence, as Google
    /// Calendar splits a series. From the first occurrence, the whole
    /// series changes instead.
    private func updateFollowing(token: String, original: CalendarEvent, series: String, draft: NewEvent,
                                 notesText: String, calendar: Calendar) async throws {
        let path = eventPath(original.calendarID, series)
        let current = try await send("GET", path, query: [], body: nil, token: token)
        let master = try JSONDecoder().decode(GoogleEvent.self, from: current)
        let cut = original.originalStart ?? original.start
        if let first = master.start.flatMap({ GoogleDate.parse($0, calendar: calendar) })?.date, cut <= first {
            return try await update(token: token, original: original, draft: draft, notesText: notesText,
                                    scope: .all, calendar: calendar)
        }
        let split = try RecurrenceSplit(master: current, original: original, draft: draft, notesText: notesText,
                                        calendar: calendar)
        var query = [URLQueryItem(name: "sendUpdates", value: split.notify ? "all" : "none")]
        if split.hasConference { query.append(URLQueryItem(name: "conferenceDataVersion", value: "1")) }
        // The new series first: a failure then leaves the old one whole.
        _ = try await send("POST", "/calendars/\(FormEncoding.escape(original.calendarID))/events",
                           query: query, body: split.newSeries, token: token)
        let rules = Recurrence.truncate(master.recurrence ?? [], before: cut, allDay: original.isAllDay, calendar: calendar)
        _ = try await send("PATCH", path, query: [URLQueryItem(name: "sendUpdates", value: split.notify ? "all" : "none")],
                           body: try JSONSerialization.data(withJSONObject: ["recurrence": rules]), token: token)
    }

    /// A POST with a JSON body, its answer's body.
    func post(_ path: String, body: Data, token: String) async throws -> Data {
        try await send("POST", path, query: [], body: body, token: token)
    }

    private func eventPath(_ calendarID: String, _ eventID: String) -> String {
        "/calendars/\(FormEncoding.escape(calendarID))/events/\(FormEncoding.escape(eventID))"
    }

    /// Token of the next page, or `nil` to stop. An empty or repeated token
    /// would otherwise loop forever.
    private static func next(_ token: String?, after previous: String?) -> String? {
        guard let token, !token.isEmpty, token != previous else { return nil }
        return token
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], token: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: await send("GET", path, query: query, body: nil, token: token))
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, token: String) async throws -> Data {
        var c = URLComponents(string: Self.base)!
        c.percentEncodedPath += path
        if !query.isEmpty { c.percentEncodedQueryItems = FormEncoding.percentEncoded(query) }
        var request = URLRequest(url: c.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.from(status: response.statusCode, body: data)
        }
        return data
    }
}

extension CalendarInfo {
    /// Fresh calendar list from Google, keeping the user's on/off choice
    /// for calendars already known.
    public static func merge(fresh: [CalendarInfo], previous: [CalendarInfo]) -> [CalendarInfo] {
        let known = Dictionary(previous.map { ($0.id, $0.enabled) }, uniquingKeysWith: { a, _ in a })
        return fresh.map { info in
            var info = info
            if let enabled = known[info.id] { info.enabled = enabled }
            return info
        }
    }
}
