import AppKit
import CalbarCore

/// Zoom for new events: the user's Zoom app, its sign-in, and creating
/// meetings. The client and the refresh token live in the Keychain; Zoom
/// rotates the refresh token on every refresh, so each answer replaces it.
@MainActor
final class ZoomAuth: ObservableObject {
    enum Failure: Error {
        case notConnected
    }

    @Published private(set) var client: ZoomClient?
    @Published private(set) var isConnected = false
    @Published private(set) var isSigningIn = false
    @Published var error: String?

    private let http: HTTPClient
    private var accessToken: (token: String, expiry: Date)?
    private var signIn: Task<Void, Never>?

    private static let clientAccount = "client"
    private static let tokenAccount = "refresh-token"

    init(http: HTTPClient = URLSession.shared) {
        self.http = http
        if let json = try? Keychain.read(account: Self.clientAccount, service: Keychain.zoomService),
           let data = json.data(using: .utf8) {
            client = try? JSONDecoder().decode(ZoomClient.self, from: data)
        }
        isConnected = ((try? Keychain.read(account: Self.tokenAccount, service: Keychain.zoomService)) ?? nil) != nil
    }

    /// Keeps what the user typed, as they type, so closing the settings
    /// loses nothing. The secret goes to the Keychain with the ID.
    func save(clientID: String, clientSecret: String) {
        let client = ZoomClient(clientID: clientID, clientSecret: clientSecret)
        guard client != self.client else { return }
        do {
            let data = try JSONEncoder().encode(client)
            try Keychain.save(String(decoding: data, as: UTF8.self), account: Self.clientAccount, service: Keychain.zoomService)
            self.client = client
        } catch {
            self.error = describe(error)
        }
    }

    /// Saves the app's Client ID (and secret) then signs in.
    func connect(clientID: String, clientSecret: String) {
        save(clientID: clientID, clientSecret: clientSecret)
        guard let client, !client.clientID.isEmpty else { return }
        signIn?.cancel()
        signIn = Task { await runSignIn(client) }
    }

    func cancelSignIn() {
        signIn?.cancel()
    }

    func disconnect() {
        Keychain.delete(account: Self.tokenAccount, service: Keychain.zoomService)
        accessToken = nil
        isConnected = false
    }

    private func runSignIn(_ client: ZoomClient) async {
        isSigningIn = true
        error = nil
        defer { isSigningIn = false }
        do {
            let state = UUID().uuidString
            let server = try LoopbackServer(expectedState: state, port: ZoomOAuth.redirectPort)
            defer { server.stop() }
            _ = try await server.start()
            let redirectURI = ZoomOAuth.redirectURI
            let pkce = PKCE()
            NSWorkspace.shared.open(ZoomOAuth.authorizationURL(client: client, redirectURI: redirectURI,
                                                               pkce: pkce, state: state))
            let timeout = Task {
                try await Task.sleep(for: .seconds(300))
                server.cancel()
            }
            defer { timeout.cancel() }
            let callback = try await withTaskCancellationHandler {
                try await server.waitForCallback()
            } onCancel: {
                server.cancel()
            }
            let code = try GoogleOAuth.parseCallback(callback, expectedState: state)
            let (data, response) = try await http.send(ZoomOAuth.codeExchangeRequest(
                client: client, code: code, redirectURI: redirectURI, verifier: pkce.verifier))
            try remember(GoogleOAuth.parseTokenResponse(data: data, status: response.statusCode))
            isConnected = true
            NSLog("Calbar: Zoom connected")
        } catch is CancellationError {
            return
        } catch {
            NSLog("Calbar: Zoom sign-in failed: %@", "\(error)")
            self.error = describe(error)
        }
    }

    private func remember(_ tokens: TokenResponse) throws {
        if let refresh = tokens.refreshToken {
            try Keychain.save(refresh, account: Self.tokenAccount, service: Keychain.zoomService)
        }
        accessToken = (tokens.accessToken, Date().addingTimeInterval(TimeInterval(tokens.expiresIn) - 60))
    }

    private func token() async throws -> String {
        if let accessToken, accessToken.expiry > Date() { return accessToken.token }
        guard let client, let refresh = try Keychain.read(account: Self.tokenAccount, service: Keychain.zoomService) else {
            throw Failure.notConnected
        }
        let (data, response) = try await http.send(ZoomOAuth.refreshRequest(client: client, refreshToken: refresh))
        do {
            let tokens = try GoogleOAuth.parseTokenResponse(data: data, status: response.statusCode)
            try remember(tokens)
            return tokens.accessToken
        } catch OAuthError.invalidGrant {
            // Expired after 90 days unused, or revoked: sign in again.
            disconnect()
            throw Failure.notConnected
        }
    }

    /// A meeting for a new event, in the user's time zone.
    func createMeeting(topic: String, start: Date, end: Date, agenda: String) async throws -> ZoomMeeting {
        let token = try await token()
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        let request = try ZoomAPI.createRequest(token: token, topic: topic, start: start, minutes: minutes,
                                                timeZone: TimeZone.current.identifier, agenda: agenda)
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { accessToken = nil }
            throw APIError.http(status: response.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        NSLog("Calbar: Zoom meeting created")
        return try ZoomAPI.parseMeeting(data)
    }
}
