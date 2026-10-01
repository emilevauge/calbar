import Foundation
import Testing
@testable import CalbarCore

@Suite struct GoogleOAuthTests {
    let client = OAuthClient(clientID: "id.apps.googleusercontent.com", clientSecret: "GOCSPX-s")

    @Test func loadsDesktopClientJSON() throws {
        let json = #"{"installed": {"client_id": "id.apps.googleusercontent.com", "client_secret": "GOCSPX-s", "redirect_uris": ["http://localhost"]}}"#
        #expect(try OAuthClient.load(json: Data(json.utf8)) == client)
    }

    @Test func pkceMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomPKCEHasValidLength() {
        let pkce = PKCE()
        #expect((43...128).contains(pkce.verifier.count))
        #expect(!pkce.verifier.contains("="))
    }

    @Test func authorizationURLCarriesAllParameters() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = GoogleOAuth.authorizationURL(
            client: client, redirectURI: "http://127.0.0.1:5555", pkce: pkce, state: "st", loginHint: "me@x.com"
        )
        let items = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a }
        )
        #expect(url.host == "accounts.google.com")
        #expect(items["client_id"] == client.clientID)
        #expect(items["redirect_uri"] == "http://127.0.0.1:5555")
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == GoogleOAuth.scopes)
        #expect(items["scope"]?.hasPrefix("openid email https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events ") == true)
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["access_type"] == "offline")
        #expect(items["prompt"] == "consent")
        #expect(items["state"] == "st")
        #expect(items["login_hint"] == "me@x.com")
    }

    @Test func parsesCallback() throws {
        let ok = URLComponents(string: "http://127.0.0.1/?state=st&code=4/abc")!
        #expect(try GoogleOAuth.parseCallback(ok, expectedState: "st") == "4/abc")

        let denied = URLComponents(string: "http://127.0.0.1/?error=access_denied&state=st")!
        #expect(throws: OAuthError.denied("access_denied")) { try GoogleOAuth.parseCallback(denied, expectedState: "st") }

        let forged = URLComponents(string: "http://127.0.0.1/?state=other&code=x")!
        #expect(throws: OAuthError.stateMismatch) { try GoogleOAuth.parseCallback(forged, expectedState: "st") }

        // A local request without the right state cannot abort sign-in.
        let forgedError = URLComponents(string: "http://127.0.0.1/?error=access_denied")!
        #expect(throws: OAuthError.stateMismatch) { try GoogleOAuth.parseCallback(forgedError, expectedState: "st") }
    }

    @Test func classifiesLoopbackRequests() {
        func kind(_ query: String) -> CallbackKind {
            GoogleOAuth.classifyCallback(URLComponents(string: "http://127.0.0.1/" + query)!, expectedState: "st")
        }
        #expect(kind("?state=st&code=4/abc") == .granted)
        #expect(kind("?state=st&error=access_denied") == .refused)
        #expect(kind("?state=st") == .refused)
        #expect(kind("?state=st&code=") == .refused)
        // Requests without the expected state are ignored, not delivered.
        #expect(kind("") == .unrelated)
        #expect(kind("?error=access_denied") == .unrelated)
        #expect(kind("?state=other&code=x") == .unrelated)
    }

    @Test func codeExchangeRequestIsFormPost() throws {
        let req = GoogleOAuth.codeExchangeRequest(client: client, code: "4/abc", redirectURI: "http://127.0.0.1:5555", verifier: "v")
        #expect(req.httpMethod == "POST")
        #expect(req.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(req.httpBody), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=4%2Fabc"))
        #expect(body.contains("code_verifier=v"))
        #expect(body.contains("client_secret=GOCSPX-s"))
    }

    @Test func parsesTokenResponse() throws {
        let json = #"{"access_token": "ya29.x", "expires_in": 3599, "refresh_token": "1//r", "id_token": "h.p.s", "token_type": "Bearer"}"#
        let t = try GoogleOAuth.parseTokenResponse(data: Data(json.utf8), status: 200)
        #expect(t.accessToken == "ya29.x")
        #expect(t.expiresIn == 3599)
        #expect(t.refreshToken == "1//r")
    }

    @Test func invalidGrantMeansReconnect() {
        let json = #"{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}"#
        #expect(throws: OAuthError.invalidGrant) {
            try GoogleOAuth.parseTokenResponse(data: Data(json.utf8), status: 400)
        }
    }

    @Test func readsEmailFromIDToken() {
        let payload = Base64URL.encode(Data(#"{"email": "alice@example.com", "email_verified": true}"#.utf8))
        #expect(GoogleOAuth.email(fromIDToken: "eyJhbGciOiJSUzI1NiJ9.\(payload).sig") == "alice@example.com")
        #expect(GoogleOAuth.email(fromIDToken: "garbage") == nil)
    }

    @Test func authorizationURLEscapesPlusInLoginHint() {
        let url = GoogleOAuth.authorizationURL(
            client: client, redirectURI: "http://127.0.0.1:5555", pkce: PKCE(), state: "st", loginHint: "a+b@x.com"
        )
        #expect(url.absoluteString.contains("login_hint=a%2Bb%40x.com"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "login_hint", value: "a+b@x.com")))
    }

    @Test func tokenResponseRedactsSecrets() throws {
        let json = #"{"access_token": "ya29.secret", "expires_in": 3599, "refresh_token": "1//refresh", "id_token": "h.idtok.s"}"#
        let t = try GoogleOAuth.parseTokenResponse(data: Data(json.utf8), status: 200)
        for text in [String(describing: t), String(reflecting: t), "\(t)"] {
            #expect(!text.contains("ya29.secret"))
            #expect(!text.contains("1//refresh"))
            #expect(!text.contains("idtok"))
            #expect(text.contains("<redacted>"))
        }
    }

    @Test func pkceRedactsVerifier() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        for text in [String(describing: pkce), String(reflecting: pkce)] {
            #expect(!text.contains(pkce.verifier))
            #expect(text.contains("<redacted>"))
        }
    }
}
