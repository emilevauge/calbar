import AppKit
import CalbarCore

/// Google sign-in and access tokens for every connected account.
@MainActor
final class GoogleAuth {
    let client: OAuthClient
    private let http: HTTPClient
    private var accessTokens: [String: (token: String, expiry: Date)] = [:]
    /// Called with the scopes Google granted each time a token refresh
    /// reports them, so the account knows whether it may answer invitations.
    var onGrantedScopes: ((_ email: String, _ scopes: [String]) -> Void)?

    init(client: OAuthClient, http: HTTPClient = URLSession.shared) {
        self.client = client
        self.http = http
    }

    /// Browser sign-in. Returns the account email and the scopes Google
    /// granted (the user may untick some on the consent screen). The refresh token goes
    /// to the Keychain. Cancelling the calling task stops the wait for the
    /// browser and throws `CancellationError`.
    func signIn(loginHint: String? = nil) async throws -> (email: String, scopes: [String]?) {
        let state = UUID().uuidString
        let server = try LoopbackServer(expectedState: state)
        defer { server.stop() }
        let port = try await server.start()
        try Task.checkCancellation()

        let redirectURI = "http://127.0.0.1:\(port)"
        let pkce = PKCE()
        NSWorkspace.shared.open(GoogleOAuth.authorizationURL(
            client: client, redirectURI: redirectURI, pkce: pkce, state: state, loginHint: loginHint
        ))

        // Give up after 5 minutes if the browser tab was abandoned.
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
        let (data, response) = try await http.send(GoogleOAuth.codeExchangeRequest(
            client: client, code: code, redirectURI: redirectURI, verifier: pkce.verifier
        ))
        let tokens = try GoogleOAuth.parseTokenResponse(data: data, status: response.statusCode)
        guard let refreshToken = tokens.refreshToken else { throw OAuthError.missingRefreshToken }
        guard let email = tokens.idToken.flatMap(GoogleOAuth.email(fromIDToken:)) else { throw OAuthError.missingEmail }

        try Keychain.save(refreshToken, account: email)
        remember(tokens, for: email)
        return (email, tokens.grantedScopes)
    }

    /// Cached access token, refreshed when expired or when `forceRefresh`
    /// is set (after a 401). Throws `OAuthError.invalidGrant` when the
    /// account must sign in again, `Keychain.Failure` when the token
    /// cannot be read.
    func accessToken(for email: String, forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let cached = accessTokens[email], cached.expiry > Date() {
            return cached.token
        }
        guard let refreshToken = try Keychain.read(account: email) else { throw OAuthError.invalidGrant }
        let (data, response) = try await http.send(GoogleOAuth.refreshRequest(client: client, refreshToken: refreshToken))
        let tokens = try GoogleOAuth.parseTokenResponse(data: data, status: response.statusCode)
        remember(tokens, for: email)
        if let scopes = tokens.grantedScopes { onGrantedScopes?(email, scopes) }
        return tokens.accessToken
    }

    func signOut(_ email: String) async {
        if let refreshToken = try? Keychain.read(account: email) {
            _ = try? await http.send(GoogleOAuth.revokeRequest(token: refreshToken))
        }
        Keychain.delete(account: email)
        accessTokens[email] = nil
    }

    private func remember(_ tokens: TokenResponse, for email: String) {
        // One minute of margin so a token never expires mid-request.
        accessTokens[email] = (tokens.accessToken, Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 60)))
    }
}
