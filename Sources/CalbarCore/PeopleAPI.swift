import Foundation

/// Guest suggestions from Google: the user's contacts, the people they
/// emailed ("other contacts"), and their Workspace directory. Each needs
/// its own read-only scope; a source the account was not granted, or
/// whose API is off, answers an error that the caller skips.
public struct PeopleAPI: Sendable {
    public static let base = "https://people.googleapis.com/v1"
    public static let contactsScope = "https://www.googleapis.com/auth/contacts.readonly"
    public static let otherContactsScope = "https://www.googleapis.com/auth/contacts.other.readonly"
    public static let directoryScope = "https://www.googleapis.com/auth/directory.readonly"
    public static let scopes: Set<String> = [contactsScope, otherContactsScope, directoryScope]

    public enum Source: CaseIterable, Sendable {
        case contacts, otherContacts, directory

        var scope: String {
            switch self {
            case .contacts: PeopleAPI.contactsScope
            case .otherContacts: PeopleAPI.otherContactsScope
            case .directory: PeopleAPI.directoryScope
            }
        }

        var path: String {
            switch self {
            case .contacts: "/people:searchContacts"
            case .otherContacts: "/otherContacts:search"
            case .directory: "/people:searchDirectoryPeople"
            }
        }
    }

    private let http: HTTPClient

    public init(http: HTTPClient = URLSession.shared) {
        self.http = http
    }

    /// Sources `granted` allows.
    public static func sources(granted: [String]?) -> [Source] {
        let set = Set(granted ?? [])
        return Source.allCases.filter { set.contains($0.scope) }
    }

    public static func request(_ source: Source, query: String, token: String) -> URLRequest {
        var c = URLComponents(string: base + source.path)!
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "readMask", value: "names,emailAddresses"),
            URLQueryItem(name: "pageSize", value: "10"),
        ]
        if source == .directory {
            items.append(URLQueryItem(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"))
        }
        c.percentEncodedQueryItems = FormEncoding.percentEncoded(items)
        var request = URLRequest(url: c.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func search(_ source: Source, query: String, token: String) async throws -> [ContactIndex.Contact] {
        let (data, response) = try await http.send(Self.request(source, query: query, token: token))
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try Self.parse(data)
    }

    /// Contacts of a search answer: `results[].person` for contacts and
    /// other contacts, `people[]` for the directory. One per email.
    public static func parse(_ data: Data) throws -> [ContactIndex.Contact] {
        struct Name: Decodable { let displayName: String? }
        struct Email: Decodable { let value: String? }
        struct PersonJSON: Decodable { let names: [Name]?; let emailAddresses: [Email]? }
        struct Result: Decodable { let person: PersonJSON? }
        struct Answer: Decodable { let results: [Result]?; let people: [PersonJSON]? }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        let people = (answer.results ?? []).compactMap(\.person) + (answer.people ?? [])
        return people.flatMap { person -> [ContactIndex.Contact] in
            let name = person.names?.first?.displayName.flatMap { $0.isEmpty ? nil : $0 }
            return (person.emailAddresses ?? []).compactMap(\.value).map { ContactIndex.Contact(email: $0, name: name) }
        }
    }
}
