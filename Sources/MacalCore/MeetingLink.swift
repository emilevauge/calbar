import Foundation

/// Video conference link attached to an event.
public struct MeetingLink: Equatable, Codable, Sendable {
    public enum Provider: String, Codable, Sendable {
        case meet, zoom, teams, webex, around, whereby, other

        public var displayName: String {
            switch self {
            case .meet: return "Google Meet"
            case .zoom: return "Zoom"
            case .teams: return "Teams"
            case .webex: return "Webex"
            case .around: return "Around"
            case .whereby: return "Whereby"
            case .other: return "Video call"
            }
        }

        static func forHost(_ host: String) -> Provider {
            let h = host.lowercased()
            if h == "meet.google.com" { return .meet }
            if h == "zoom.us" || h.hasSuffix(".zoom.us") { return .zoom }
            if h == "teams.microsoft.com" || h == "teams.live.com" { return .teams }
            if h.hasSuffix(".webex.com") { return .webex }
            if h == "around.co" || h.hasSuffix(".around.co") { return .around }
            if h == "whereby.com" { return .whereby }
            return .other
        }
    }

    public let url: URL
    public let provider: Provider

    public init(url: URL, provider: Provider) {
        self.url = url
        self.provider = provider
    }

    /// URL that opens the provider's desktop app directly, when we know how
    /// to build one. Only Zoom meeting links ("/j/<id>") qualify: the https
    /// link would otherwise leave a "Launch meeting" tab behind in the browser.
    public var nativeURL: URL? {
        guard provider == .zoom else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "j", let host = url.host else { return nil }
        var c = URLComponents()
        c.scheme = "zoommtg"
        c.host = host
        c.path = "/join"
        // Percent-encoded on both sides: a "%2B" in the password must not
        // come back as a raw "+", which Zoom would read as a space.
        var items = [
            URLQueryItem(name: "action", value: "join"),
            URLQueryItem(name: "confno", value: FormEncoding.escape(parts[2]))
        ]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        if let pwd = query.first(where: { $0.name == "pwd" })?.value {
            items.append(URLQueryItem(name: "pwd", value: pwd))
        }
        c.percentEncodedQueryItems = items
        return c.url
    }
}
