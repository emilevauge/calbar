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
    /// was signed in before Macal asked for it and must reconnect.
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

/// Client for the Calendar API endpoints Macal needs: the calendar list
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
