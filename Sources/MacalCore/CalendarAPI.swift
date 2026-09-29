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
    case http(status: Int, body: String)
    case invalidResponse
}

/// Read-only client for the two Calendar API endpoints Macal needs.
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

    /// Token of the next page, or `nil` to stop. An empty or repeated token
    /// would otherwise loop forever.
    private static func next(_ token: String?, after previous: String?) -> String? {
        guard let token, !token.isEmpty, token != previous else { return nil }
        return token
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], token: String) async throws -> T {
        var c = URLComponents(string: Self.base)!
        c.percentEncodedPath += path
        c.percentEncodedQueryItems = FormEncoding.percentEncoded(query)
        var request = URLRequest(url: c.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.send(request)
        switch response.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.http(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
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
