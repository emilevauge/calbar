import Foundation
import CryptoKit

public struct OAuthClient: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Reads the JSON Google Cloud Console downloads for a "Desktop app"
    /// client. Throws for any other client type or empty credentials.
    public static func load(json: Data) throws -> OAuthClient {
        struct File: Decodable {
            struct Installed: Decodable {
                let client_id: String
                let client_secret: String
            }
            let installed: Installed
        }
        let file = try JSONDecoder().decode(File.self, from: json)
        let id = file.installed.client_id.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = file.installed.client_secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { throw OAuthClientFile.InvalidClient() }
        return OAuthClient(clientID: id, clientSecret: secret)
    }
}

/// The secret stays out of logs and debugger output.
extension OAuthClient: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "OAuthClient(clientID: \(clientID), clientSecret: <redacted>)" }
    public var debugDescription: String { description }
}

/// Proof Key for Code Exchange (RFC 7636), S256 method.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public init() {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        self.init(verifier: Base64URL.encode(Data(bytes)))
    }
}

extension PKCE: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "PKCE(verifier: <redacted>, challenge: \(challenge))" }
    public var debugDescription: String { description }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

public struct TokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let expiresIn: Int
    /// Only returned on the first code exchange.
    public let refreshToken: String?
    public let idToken: String?
    /// Space-separated scopes of the grant, as Google returns them.
    public let scope: String?

    /// `scope` as a list, `nil` when Google did not send it.
    public var grantedScopes: [String]? {
        scope.map { $0.split(separator: " ").map(String.init) }
    }

    enum CodingKeys: String, CodingKey {
        case scope
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

/// Tokens stay out of logs and debugger output.
extension TokenResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        func redacted(_ s: String?) -> String { s == nil ? "nil" : "<redacted>" }
        return "TokenResponse(accessToken: <redacted>, expiresIn: \(expiresIn), "
            + "refreshToken: \(redacted(refreshToken)), idToken: \(redacted(idToken)))"
    }
    public var debugDescription: String { description }
}

public enum OAuthError: Error, Equatable {
    /// Refresh token revoked or expired: the user must sign in again.
    case invalidGrant
    case denied(String)
    case stateMismatch
    case missingCode
    case missingRefreshToken
    case missingEmail
    case server(status: Int, body: String)
}

/// What a request on the loopback server's "/" is.
public enum CallbackKind: Equatable, Sendable {
    /// No or wrong `state`: not Google's redirect for this sign-in.
    case unrelated
    /// Google's redirect with an authorization code.
    case granted
    /// Google's redirect without a code (user refused, or an error).
    case refused
}

public enum GoogleOAuth {
    /// `calendar.readonly` reads the calendar list, which `calendar.events`
    /// does not cover; `calendar.events` lets Calbar answer invitations.
    public static let scopes = "openid email https://www.googleapis.com/auth/calendar.readonly \(eventsScope)"
    public static let eventsScope = "https://www.googleapis.com/auth/calendar.events"
    /// Scopes that allow changing an event's attendee list.
    public static let writeScopes: Set<String> = [eventsScope, "https://www.googleapis.com/auth/calendar"]
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    public static func authorizationURL(
        client: OAuthClient,
        redirectURI: String,
        pkce: PKCE,
        state: String,
        loginHint: String?
    ) -> URL {
        var c = URLComponents(string: authEndpoint)!
        var items = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Offline access plus a forced consent screen: Google only sends
            // a refresh token when both are present.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        c.percentEncodedQueryItems = FormEncoding.percentEncoded(items)
        return c.url!
    }

    /// Lets the loopback server ignore requests that are not the redirect
    /// of this sign-in: any local process can hit the port.
    public static func classifyCallback(_ callback: URLComponents, expectedState: String) -> CallbackKind {
        let items = callback.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { return .unrelated }
        if let code = value("code"), !code.isEmpty { return .granted }
        return .refused
    }

    /// Authorization code from the redirect Google sends to the loopback server.
    public static func parseCallback(_ callback: URLComponents, expectedState: String) throws -> String {
        let q = Dictionary(
            (callback.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a }
        )
        // State first: any local process can hit the loopback port, and a
        // forged "?error=..." must not abort a sign-in in progress.
        guard q["state"] == expectedState else { throw OAuthError.stateMismatch }
        if let error = q["error"] { throw OAuthError.denied(error) }
        guard let code = q["code"], !code.isEmpty else { throw OAuthError.missingCode }
        return code
    }

    public static func codeExchangeRequest(client: OAuthClient, code: String, redirectURI: String, verifier: String) -> URLRequest {
        post(tokenEndpoint, [
            ("code", code),
            ("client_id", client.clientID),
            ("client_secret", client.clientSecret),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier),
        ])
    }

    public static func refreshRequest(client: OAuthClient, refreshToken: String) -> URLRequest {
        post(tokenEndpoint, [
            ("client_id", client.clientID),
            ("client_secret", client.clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ])
    }

    public static func revokeRequest(token: String) -> URLRequest {
        post(revokeEndpoint, [("token", token)])
    }

    public static func parseTokenResponse(data: Data, status: Int) throws -> TokenResponse {
        if (200..<300).contains(status) {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        }
        struct Failure: Decodable { let error: String }
        if let failure = try? JSONDecoder().decode(Failure.self, from: data), failure.error == "invalid_grant" {
            throw OAuthError.invalidGrant
        }
        throw OAuthError.server(status: status, body: String(decoding: data, as: UTF8.self))
    }

    /// Account email from the `id_token` payload. The token comes straight
    /// from Google over TLS, so its signature is not checked here.
    public static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let data = Base64URL.decode(String(parts[1])) else { return nil }
        struct Claims: Decodable { let email: String? }
        return (try? JSONDecoder().decode(Claims.self, from: data))?.email
    }

    private static func post(_ url: URL, _ form: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(form)
        return request
    }
}
