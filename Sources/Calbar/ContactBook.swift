import Foundation
import CalbarCore

/// Guest suggestions for the event editor: people met in the loaded
/// events and in the last two months of the primary calendars, searched
/// locally at once, then the Google contacts, other contacts and directory
/// of the accounts granted them, searched as the user types.
@MainActor
final class ContactBook: ObservableObject {
    @Published private(set) var index = ContactIndex()
    /// Meeting rooms seen in the events, most used first: the rooms the
    /// editor can book. Listing all of an organization's rooms needs the
    /// Admin Directory API, open to administrators only.
    @Published private(set) var rooms: [Person] = []
    private let store: EventStore
    private let accounts: AccountStore
    private var gatheredAt: Date?
    private var gathering = false

    init(store: EventStore, accounts: AccountStore) {
        self.store = store
        self.accounts = accounts
    }

    /// No account was granted a Google people source: reconnecting adds them.
    var needsReconnectForGoogle: Bool {
        !accounts.accounts.isEmpty && accounts.accounts.allSatisfy { $0.contactSources.isEmpty }
    }

    /// Refreshes from what is loaded, then gathers the recent events if needed.
    func prepare() {
        let own = ownAddresses
        var quick = index
        quick.add(events: store.loadedEvents, excluding: own)
        index = quick
        rooms = Self.rooms(in: store.loadedEvents)
        if let gatheredAt, Date().timeIntervalSince(gatheredAt) < 6 * 3600 { return }
        guard !gathering else { return }
        gathering = true
        Task {
            let recent = await store.recentPrimaryEvents()
            var full = ContactIndex()
            full.add(events: store.loadedEvents + recent, excluding: own)
            index = full
            rooms = Self.rooms(in: store.loadedEvents + recent)
            gatheredAt = Date()
            gathering = false
        }
    }

    /// Google matches for `query`, without the user's own addresses.
    func searchGoogle(_ query: String) async -> [ContactIndex.Contact] {
        let own = ownAddresses
        return await store.searchPeople(query).filter { !own.contains($0.email.lowercased()) }
    }

    /// One per email, the name Google gave it, most booked first.
    static func rooms(in events: [CalendarEvent]) -> [Person] {
        var count: [String: Int] = [:]
        var byEmail: [String: Person] = [:]
        var seen = Set<String>()
        for event in events where seen.insert(event.occurrenceKey).inserted {
            for room in event.rooms {
                let key = room.email.lowercased()
                count[key, default: 0] += 1
                if byEmail[key]?.name == nil { byEmail[key] = room }
            }
        }
        return byEmail.values.sorted {
            (-(count[$0.email.lowercased()] ?? 0), $0.displayName) < (-(count[$1.email.lowercased()] ?? 0), $1.displayName)
        }
    }

    private var ownAddresses: Set<String> { Set(accounts.accounts.map { $0.email.lowercased() }) }
}
