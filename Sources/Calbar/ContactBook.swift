import Foundation
import CalbarCore

/// Guest suggestions for the event editor: people met in the loaded
/// events and in the last two months of the primary calendars, searched
/// locally at once, then the Google contacts, other contacts and directory
/// of the accounts granted them, searched as the user types.
@MainActor
final class ContactBook: ObservableObject {
    @Published private(set) var index = ContactIndex()
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
        if let gatheredAt, Date().timeIntervalSince(gatheredAt) < 6 * 3600 { return }
        guard !gathering else { return }
        gathering = true
        Task {
            let recent = await store.recentPrimaryEvents()
            var full = ContactIndex()
            full.add(events: store.loadedEvents + recent, excluding: own)
            index = full
            gatheredAt = Date()
            gathering = false
        }
    }

    /// Google matches for `query`, without the user's own addresses.
    func searchGoogle(_ query: String) async -> [ContactIndex.Contact] {
        let own = ownAddresses
        return await store.searchPeople(query).filter { !own.contains($0.email.lowercased()) }
    }

    private var ownAddresses: Set<String> { Set(accounts.accounts.map { $0.email.lowercased() }) }
}
