import Foundation

/// People to suggest as guests: everyone met in the loaded events, and
/// address book entries, searched by the start of a name word or of the
/// email. People met more often come first.
public struct ContactIndex: Sendable {
    public struct Contact: Equatable, Hashable, Sendable {
        public let email: String
        public let name: String?

        public init(email: String, name: String?) {
            self.email = email
            self.name = name
        }

        /// "Alice Martin <alice@example.com>", or the email alone.
        public var label: String { name.map { "\($0) <\(email)>" } ?? email }
    }

    private var entries: [String: (contact: Contact, count: Int)] = [:]

    public init() {}

    /// Attendees and organizers of `events`, except `excluding` (the
    /// user's own addresses), counted once per event.
    public mutating func add(events: [CalendarEvent], excluding own: Set<String>) {
        for event in events {
            var people = event.attendees.filter { !$0.isSelf }.map(\.person)
            if let organizer = event.organizer { people.append(organizer) }
            var seen = Set<String>()
            for person in people {
                let key = person.email.lowercased()
                guard !own.contains(key), !key.hasSuffix("calendar.google.com"), seen.insert(key).inserted else { continue }
                add(Contact(email: person.email, name: person.name), weight: 1)
            }
        }
    }

    /// Address book entries count less than people actually met.
    public mutating func add(contacts: [Contact]) {
        for contact in contacts { add(contact, weight: 0) }
    }

    private mutating func add(_ contact: Contact, weight: Int) {
        let key = contact.email.lowercased()
        if let known = entries[key] {
            let name = known.contact.name ?? contact.name
            entries[key] = (Contact(email: known.contact.email, name: name), known.count + weight)
        } else {
            entries[key] = (contact, weight)
        }
    }

    /// At most `limit` contacts whose name has a word, or whose email,
    /// starting with `query`, case and accents ignored; `excluding`
    /// emails already added.
    public func search(_ query: String, excluding: Set<String> = [], limit: Int = 6) -> [Contact] {
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        let skip = Set(excluding.map { $0.lowercased() })
        return entries.values
            .filter { !skip.contains($0.contact.email.lowercased()) && Self.matches($0.contact, q) }
            .sorted { ($1.count, $0.contact.name ?? $0.contact.email) < ($0.count, $1.contact.name ?? $1.contact.email) }
            .prefix(limit)
            .map(\.contact)
    }

    private static func matches(_ c: Contact, _ q: String) -> Bool {
        if fold(c.email).hasPrefix(q) { return true }
        guard let name = c.name else { return false }
        let folded = fold(name)
        if folded.hasPrefix(q) { return true }
        return folded.split(whereSeparator: { $0 == " " || $0 == "-" }).contains { $0.hasPrefix(q) }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
