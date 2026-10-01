import Foundation
import Testing
@testable import CalbarCore

@Suite struct PeopleAPITests {
    @Test func parsesSearchAnswers() throws {
        let contacts = Data(#"{"results":[{"person":{"names":[{"displayName":"Alice Martin"}],"emailAddresses":[{"value":"alice@example.com"},{"value":"a.m@example.org"}]}},{"person":{"emailAddresses":[{"value":"bob@example.com"}]}}]}"#.utf8)
        let parsed = try PeopleAPI.parse(contacts)
        #expect(parsed == [.init(email: "alice@example.com", name: "Alice Martin"),
                           .init(email: "a.m@example.org", name: "Alice Martin"),
                           .init(email: "bob@example.com", name: nil)])
        let directory = Data(#"{"people":[{"names":[{"displayName":"Carla Diaz"}],"emailAddresses":[{"value":"carla@traefik.io"}]}]}"#.utf8)
        #expect(try PeopleAPI.parse(directory) == [.init(email: "carla@traefik.io", name: "Carla Diaz")])
        #expect(try PeopleAPI.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func requestsAndGrantedSources() {
        let r = PeopleAPI.request(.directory, query: "al ice", token: "t")
        let url = r.url!.absoluteString
        #expect(url.hasPrefix("https://people.googleapis.com/v1/people:searchDirectoryPeople?"))
        #expect(url.contains("query=al%20ice"))
        #expect(url.contains("sources=DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"))
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(!PeopleAPI.request(.contacts, query: "a", token: "t").url!.absoluteString.contains("sources="))
        #expect(PeopleAPI.sources(granted: [PeopleAPI.otherContactsScope, "openid"]) == [.otherContacts])
        #expect(PeopleAPI.sources(granted: nil).isEmpty)
    }
}
