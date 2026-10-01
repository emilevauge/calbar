import Foundation
import Testing
@testable import CalbarCore

final class StubHTTP: HTTPClient, @unchecked Sendable {
    var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            Issue.record("unexpected request: \(request.url?.absoluteString ?? "")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data("no stub".utf8), response)
        }
        let (status, body) = responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@Suite struct CalendarAPITests {
    let source = CalendarInfo(id: "team#x@group.calendar.google.com", name: "Team", colorHex: "#16a765", isPrimary: false, enabled: true)

    @Test func fetchesEventsAcrossPages() async throws {
        let page1 = #"{"items": [{"id": "a", "start": {"dateTime": "2026-09-29T10:00:00Z"}, "end": {"dateTime": "2026-09-29T10:30:00Z"}}], "nextPageToken": "p2"}"#
        let page2 = #"{"items": [{"id": "b", "start": {"dateTime": "2026-09-29T11:00:00Z"}, "end": {"dateTime": "2026-09-29T11:30:00Z"}}]}"#
        let http = StubHTTP([(200, page1), (200, page2)])
        let api = CalendarAPI(http: http)

        let events = try await api.events(
            token: "tok", source: source, accountEmail: "me@x.com",
            from: TestClock.date("2026-09-29T00:00:00+02:00"),
            to: TestClock.date("2026-10-01T00:00:00+02:00"),
            calendar: TestClock.paris
        )

        #expect(events.map(\.title) == ["(No title)", "(No title)"])
        #expect(http.requests.count == 2)
        let first = try #require(http.requests.first?.url)
        #expect(first.absoluteString.hasPrefix("https://www.googleapis.com/calendar/v3/calendars/team%23x%40group.calendar.google.com/events?"))
        let items = URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "singleEvents", value: "true")))
        #expect(items.contains(URLQueryItem(name: "timeMin", value: "2026-09-28T22:00:00Z")))
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let second = URLComponents(url: http.requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(second.contains(URLQueryItem(name: "pageToken", value: "p2")))
    }

    @Test func mapsUnauthorized() async {
        let api = CalendarAPI(http: StubHTTP([(401, "{}")]))
        await #expect(throws: APIError.unauthorized) {
            try await api.calendars(token: "old")
        }
    }

    @Test func fetchesCalendarList() async throws {
        let body = ##"{"items": [{"id": "me@x.com", "summary": "Me", "primary": true, "backgroundColor": "#9fe1e7"}]}"##
        let api = CalendarAPI(http: StubHTTP([(200, body)]))
        let list = try await api.calendars(token: "t")
        #expect(list == [CalendarInfo(id: "me@x.com", name: "Me", colorHex: "#9fe1e7", isPrimary: true, enabled: true)])
    }

    @Test func mergeKeepsUserChoice() {
        let previous = [CalendarInfo(id: "a", name: "A", colorHex: "#000000", isPrimary: true, enabled: false)]
        let fresh = [
            CalendarInfo(id: "a", name: "A renamed", colorHex: "#111111", isPrimary: true, enabled: true),
            CalendarInfo(id: "b", name: "B", colorHex: "#222222", isPrimary: false, enabled: true),
        ]
        let merged = CalendarInfo.merge(fresh: fresh, previous: previous)
        #expect(merged.map(\.name) == ["A renamed", "B"])
        #expect(merged.map(\.enabled) == [false, true])
    }

    @Test func formEncodingEscapesReservedCharacters() {
        let data = FormEncoding.encode([("code", "4/0A+b c"), ("redirect_uri", "http://127.0.0.1:5000")])
        #expect(String(decoding: data, as: UTF8.self) == "code=4%2F0A%2Bb%20c&redirect_uri=http%3A%2F%2F127.0.0.1%3A5000")
    }

    @Test func stopsWhenPageTokenRepeats() async throws {
        let page = #"{"items": [], "nextPageToken": "same"}"#
        let http = StubHTTP([(200, page), (200, page)])
        _ = try await CalendarAPI(http: http).calendars(token: "t")
        #expect(http.requests.count == 2)
    }

    @Test func stopsOnEmptyPageToken() async throws {
        let http = StubHTTP([(200, #"{"items": [], "nextPageToken": ""}"#)])
        _ = try await CalendarAPI(http: http).events(
            token: "t", source: source, accountEmail: "me@x.com",
            from: TestClock.date("2026-09-29T00:00:00+02:00"),
            to: TestClock.date("2026-09-30T00:00:00+02:00"),
            calendar: TestClock.paris
        )
        #expect(http.requests.count == 1)
    }

    @Test func escapesPlusInQueryValues() async throws {
        let http = StubHTTP([
            (200, #"{"items": [], "nextPageToken": "a+b/c"}"#),
            (200, #"{"items": []}"#),
        ])
        _ = try await CalendarAPI(http: http).calendars(token: "t")
        let second = try #require(http.requests.last?.url)
        #expect(second.absoluteString.contains("pageToken=a%2Bb%2Fc"))
        let items = URLComponents(url: second, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "pageToken", value: "a+b/c")))
    }
}
