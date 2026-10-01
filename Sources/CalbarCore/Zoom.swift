import Foundation

/// The user's own Zoom OAuth app (General app, user-managed, redirect
/// `http://127.0.0.1`, scope `meeting:write:meeting`). PKCE does without
/// the secret; one given is sent as Basic auth, for apps that require it.
public struct ZoomClient: Codable, Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String?

    public init(clientID: String, clientSecret: String?) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = secret?.isEmpty == false ? secret : nil
    }
}

/// Zoom sign-in, the same loopback and PKCE flow as Google's. Zoom
/// matches a registered `http://127.0.0.1` redirect whatever the port.
public enum ZoomOAuth {
    public static let authorizeEndpoint = "https://zoom.us/oauth/authorize"
    public static let tokenEndpoint = URL(string: "https://zoom.us/oauth/token")!

    public static func authorizationURL(client: ZoomClient, redirectURI: String, pkce: PKCE, state: String) -> URL {
        var c = URLComponents(string: authorizeEndpoint)!
        c.percentEncodedQueryItems = FormEncoding.percentEncoded([
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ])
        return c.url!
    }

    public static func codeExchangeRequest(client: ZoomClient, code: String, redirectURI: String, verifier: String) -> URLRequest {
        post(client, [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("code_verifier", verifier),
            ("client_id", client.clientID),
        ])
    }

    /// Zoom rotates refresh tokens: the answer's one replaces the stored one.
    public static func refreshRequest(client: ZoomClient, refreshToken: String) -> URLRequest {
        post(client, [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", client.clientID),
        ])
    }

    private static func post(_ client: ZoomClient, _ form: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let secret = client.clientSecret {
            let basic = Data("\(client.clientID):\(secret)".utf8).base64EncodedString()
            request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = FormEncoding.encode(form)
        return request
    }
}

/// A Zoom meeting created for a new event.
public struct ZoomMeeting: Equatable, Sendable {
    public let id: Int64
    public let joinURL: URL
    public let passcode: String?

    public init(id: Int64, joinURL: URL, passcode: String?) {
        self.id = id
        self.joinURL = joinURL
        self.passcode = passcode
    }

    /// Lines added to the event's description, as Zoom's own add-on does.
    public var description: String {
        var lines = ["Join Zoom Meeting", joinURL.absoluteString, "", "Meeting ID: \(Self.spaced(id))"]
        if let passcode, !passcode.isEmpty { lines.append("Passcode: \(passcode)") }
        return lines.joined(separator: "\n")
    }

    /// "812 3456 7890", as Zoom shows ids.
    static func spaced(_ id: Int64) -> String {
        let s = String(id)
        guard s.count > 6 else { return s }
        let head = s.dropLast(8).isEmpty ? "" : String(s.dropLast(8))
        let rest = String(s.suffix(min(8, s.count)))
        let parts = [head, String(rest.prefix(4)), String(rest.suffix(4))].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

public enum ZoomAPI {
    public static let base = "https://api.zoom.us/v2"

    /// A scheduled meeting (`type` 2) for the user who signed in.
    public static func createRequest(token: String, topic: String, start: Date, minutes: Int,
                                     timeZone: String, agenda: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: base + "/users/me/meetings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        var body: [String: Any] = [
            "topic": topic,
            "type": 2,
            "start_time": formatter.string(from: start),
            "duration": max(minutes, 1),
            "timezone": timeZone,
        ]
        if !agenda.isEmpty { body["agenda"] = String(agenda.prefix(2000)) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    public static func parseMeeting(_ data: Data) throws -> ZoomMeeting {
        struct Answer: Decodable { let id: Int64; let join_url: String; let password: String? }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard let url = URL(string: answer.join_url) else { throw APIError.invalidResponse }
        return ZoomMeeting(id: answer.id, joinURL: url, passcode: answer.password)
    }
}
