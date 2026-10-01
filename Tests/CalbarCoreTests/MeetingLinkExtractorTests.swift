import Foundation
import Testing
@testable import CalbarCore

@Suite struct MeetingLinkExtractorTests {
    @Test func prefersConferenceData() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: ["https://us02web.zoom.us/j/85012345678?pwd=abc"],
            hangoutLink: "https://meet.google.com/abc-defg-hij",
            location: nil, description: nil
        )
        #expect(link?.provider == .zoom)
    }

    @Test func fallsBackToHangoutLink() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: [], hangoutLink: "https://meet.google.com/abc-defg-hij",
            location: nil, description: nil
        )
        #expect(link == MeetingLink(url: URL(string: "https://meet.google.com/abc-defg-hij")!, provider: .meet))
    }

    @Test func findsTeamsInLocation() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: [], hangoutLink: nil,
            location: "Microsoft Teams: https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0",
            description: nil
        )
        #expect(link?.provider == .teams)
        #expect(link?.url.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0")
    }

    @Test func findsZoomInHTMLDescriptionAndDecodesEntities() {
        let html = #"Join: <a href="https://acme.zoom.us/j/123?pwd=x&amp;uname=y">Zoom</a>"#
        let link = MeetingLinkExtractor.extract(conferenceURIs: [], hangoutLink: nil, location: nil, description: html)
        #expect(link?.url.absoluteString == "https://acme.zoom.us/j/123?pwd=x&uname=y")
    }

    @Test func earliestLinkInTextWins() {
        let text = "backup https://meet.google.com/abc-defg-hij then https://zoom.us/j/1"
        let link = MeetingLinkExtractor.extract(conferenceURIs: [], hangoutLink: nil, location: nil, description: text)
        #expect(link?.provider == .meet)
    }

    @Test func trimsTrailingPunctuation() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: [], hangoutLink: nil, location: nil,
            description: "Join https://whereby.com/acme."
        )
        #expect(link?.url.absoluteString == "https://whereby.com/acme")
    }

    @Test func returnsNilWithoutLink() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: [], hangoutLink: nil, location: "Everest room", description: "https://docs.google.com/x"
        )
        #expect(link == nil)
    }

    @Test func unknownConferenceHostIsOther() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: ["https://video.example.com/room"], hangoutLink: nil, location: nil, description: nil
        )
        #expect(link?.provider == .other)
        #expect(link?.provider.displayName == "Video call")
    }

    @Test func zoomNativeURL() {
        let link = MeetingLink(url: URL(string: "https://us02web.zoom.us/j/85012345678?pwd=abc")!, provider: .zoom)
        #expect(link.nativeURL?.absoluteString == "zoommtg://us02web.zoom.us/join?action=join&confno=85012345678&pwd=abc")
    }

    @Test func zoomVanityLinkHasNoNativeURL() {
        let link = MeetingLink(url: URL(string: "https://zoom.us/my/emile")!, provider: .zoom)
        #expect(link.nativeURL == nil)
    }

    @Test func findsTeamsNewMeetFormat() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: [], hangoutLink: nil,
            location: nil, description: "Join: https://teams.microsoft.com/meet/31234567890123?p=AbCdEf123 now"
        )
        #expect(link?.provider == .teams)
        #expect(link?.url.absoluteString == "https://teams.microsoft.com/meet/31234567890123?p=AbCdEf123")
    }

    @Test func meetCodeNeedsEndBoundary() {
        let link = MeetingLinkExtractor.extract(
            conferenceURIs: [], hangoutLink: nil, location: nil,
            description: "https://meet.google.com/abc-defg-hijk"
        )
        #expect(link == nil)
    }

    @Test func zoomNativeURLKeepsPercentEncodedPassword() {
        let link = MeetingLink(url: URL(string: "https://zoom.us/j/1?pwd=a%2Bb")!, provider: .zoom)
        #expect(link.nativeURL?.absoluteString == "zoommtg://zoom.us/join?action=join&confno=1&pwd=a%2Bb")
    }
}
