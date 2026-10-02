import Foundation
import Testing
@testable import CalbarCore

@Suite struct DiscordTests {
    func extract(location: String?, description: String? = nil) -> MeetingLink? {
        MeetingLinkExtractor.extract(conferenceURIs: [], hangoutLink: nil, location: location, description: description)
    }

    @Test func channelInTheLocation() {
        let link = extract(location: "#standup")
        #expect(link?.provider == .discord)
        #expect(link?.channel == "standup")
        #expect(link?.label == "Discord #standup")
        #expect(extract(location: "Discord #dev-sync, voice")?.channel == "dev-sync")
        #expect(extract(location: "Room #3") == nil)
        #expect(extract(location: "Paris") == nil)
        // Hashtags of a description are not channels.
        #expect(extract(location: nil, description: "#agenda") == nil)
    }

    @Test func urlsComeFirst() {
        let link = extract(location: "#standup https://meet.google.com/abc-defg-hij")
        #expect(link?.provider == .meet)
        #expect(extract(location: "https://discord.com/channels/1/2")?.provider == .discord)
        #expect(extract(location: nil, description: "Join https://discord.gg/abc")?.provider == .discord)
    }

    @Test func resolvesListedChannelsThenTheServer() {
        let channels = DiscordChannels.parse("#Standup https://discord.com/channels/11/22\nnot a line\n#web http://example.com")
        #expect(channels == ["standup": URL(string: "https://discord.com/channels/11/22")!])
        let standup = MeetingLink(url: DiscordChannels.home, provider: .discord, channel: "standup")
        #expect(DiscordChannels.resolve(standup, channels: channels, server: nil).absoluteString == "https://discord.com/channels/11/22")
        let other = MeetingLink(url: DiscordChannels.home, provider: .discord, channel: "other")
        #expect(DiscordChannels.resolve(other, channels: channels, server: "https://discord.com/channels/11/33").absoluteString
                == "https://discord.com/channels/11")
        #expect(DiscordChannels.resolve(other, channels: channels, server: nil) == DiscordChannels.home)
    }

    @Test func appLinks() {
        #expect(MeetingLink(url: URL(string: "https://discord.com/channels/11/22")!, provider: .discord).nativeURL?.absoluteString
                == "discord://-/channels/11/22")
        #expect(MeetingLink(url: DiscordChannels.home, provider: .discord).nativeURL?.absoluteString == "discord://-/channels/@me")
        #expect(MeetingLink(url: URL(string: "https://discord.gg/abc")!, provider: .discord).nativeURL == nil)
    }
}
