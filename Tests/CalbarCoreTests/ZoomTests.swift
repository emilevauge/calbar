import Foundation
import Testing
@testable import CalbarCore

@Suite struct ZoomTests {
    let client = ZoomClient(clientID: " abc ", clientSecret: "")

    @Test func clientTrimsAndDropsAnEmptySecret() {
        #expect(client.clientID == "abc")
        #expect(client.clientSecret == nil)
        #expect(ZoomClient(clientID: "a", clientSecret: " s ").clientSecret == "s")
    }

    @Test func authorizationURL() {
        let pkce = PKCE(verifier: "v")
        let url = ZoomOAuth.authorizationURL(client: client, redirectURI: "http://127.0.0.1:5555", pkce: pkce, state: "st")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.absoluteString.hasPrefix("https://zoom.us/oauth/authorize?"))
        #expect(items["client_id"] == "abc")
        #expect(items["redirect_uri"] == "http://127.0.0.1:5555")
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "st")
    }

    @Test func tokenRequestsUseBasicAuthOnlyWithASecret() {
        let plain = ZoomOAuth.codeExchangeRequest(client: client, code: "c", redirectURI: "r", verifier: "v")
        #expect(plain.value(forHTTPHeaderField: "Authorization") == nil)
        let body = String(decoding: plain.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code") && body.contains("code_verifier=v"))
        let secret = ZoomOAuth.refreshRequest(client: ZoomClient(clientID: "a", clientSecret: "s"), refreshToken: "t")
        #expect(secret.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("a:s".utf8).base64EncodedString())
    }

    @Test func meetingRequestAndAnswer() throws {
        let start = TestClock.date("2026-10-01T14:15:00+02:00")
        let r = try ZoomAPI.createRequest(token: "t", topic: "Review", start: start, minutes: 45,
                                          timeZone: "Europe/Paris", agenda: "")
        let j = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
        #expect(r.url?.absoluteString == "https://api.zoom.us/v2/users/me/meetings")
        #expect(j["start_time"] as? String == "2026-10-01T12:15:00Z")
        #expect(j["duration"] as? Int == 45 && j["type"] as? Int == 2 && j["agenda"] == nil)
        let m = try ZoomAPI.parseMeeting(Data(#"{"id":81234567890,"join_url":"https://zoom.us/j/81234567890?pwd=x","password":"ab12"}"#.utf8))
        #expect(m.id == 81234567890 && m.passcode == "ab12")
        #expect(m.description.contains("Meeting ID: 812 3456 7890"))
    }

    @Test func zoomLinkGoesToTheEvent() throws {
        let start = TestClock.date("2026-10-01T14:15:00+02:00")
        let zoom = ZoomMeeting(id: 81234567890, joinURL: URL(string: "https://zoom.us/j/81234567890")!, passcode: nil)
        var e = NewEvent(title: "x", start: start, end: start, calendarID: "c", addMeet: false, notes: "Agenda")
        e.zoom = zoom
        let j = try JSONSerialization.jsonObject(with: e.body()) as! [String: Any]
        #expect(j["location"] as? String == "https://zoom.us/j/81234567890")
        #expect((j["description"] as? String)?.hasPrefix("Join Zoom Meeting\nhttps://zoom.us/j/81234567890") == true)
        #expect((j["description"] as? String)?.hasSuffix("Agenda") == true)
        // The link is what Calbar's own join detection finds.
        #expect(MeetingLinkExtractor.extract(conferenceURIs: [], hangoutLink: nil, location: j["location"] as? String, description: nil)?.provider == .zoom)
    }
}
