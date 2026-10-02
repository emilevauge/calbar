import Foundation
import Testing
@testable import CalbarCore

@Suite struct DiscordTests {
    func extract(location: String?, description: String? = nil) -> MeetingLink? {
        MeetingLinkExtractor.extract(conferenceURIs: [], hangoutLink: nil, location: location, description: description)
    }

    @Test func fullLinksOnly() {
        #expect(extract(location: "https://discord.com/channels/323834733173800963/514426493091446797")?.provider == .discord)
        #expect(extract(location: nil, description: "Join https://discord.gg/abc")?.provider == .discord)
        // A channel name alone gives no link: nothing to join.
        #expect(extract(location: "#batcave") == nil)
    }

    @Test func appLinks() {
        #expect(MeetingLink(url: URL(string: "https://discord.com/channels/11/22")!, provider: .discord).nativeURL?.absoluteString
                == "discord://-/channels/11/22")
        #expect(MeetingLink(url: URL(string: "https://discord.gg/abc")!, provider: .discord).nativeURL == nil)
    }
}
