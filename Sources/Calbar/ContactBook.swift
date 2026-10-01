import Foundation
import Contacts
import CalbarCore

/// Guest suggestions for the event editor: people met in the loaded
/// events at once, then those of the last two months and the Mac's
/// address book, gathered in the background once per launch (again after
/// six hours).
@MainActor
final class ContactBook: ObservableObject {
    @Published private(set) var index = ContactIndex()
    private var gatheredAt: Date?
    private var gathering = false

    /// Refreshes from what is loaded, then gathers the rest if needed.
    func prepare(store: EventStore, accounts: AccountStore) {
        let own = Set(accounts.accounts.map { $0.email.lowercased() })
        var quick = index
        quick.add(events: store.loadedEvents, excluding: own)
        index = quick
        if let gatheredAt, Date().timeIntervalSince(gatheredAt) < 6 * 3600 { return }
        guard !gathering else { return }
        gathering = true
        Task {
            let recent = await store.recentPrimaryEvents()
            let book = await Self.addressBook()
            var full = ContactIndex()
            full.add(events: store.loadedEvents + recent, excluding: own)
            full.add(contacts: book)
            index = full
            gatheredAt = Date()
            gathering = false
        }
    }

    /// Everyone with an email in the Mac's contacts. macOS asks for access
    /// the first time; refused, there are no address book suggestions.
    private static func addressBook() async -> [ContactIndex.Contact] {
        let store = CNContactStore()
        let granted: Bool
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: granted = true
        case .notDetermined: granted = (try? await store.requestAccess(for: .contacts)) ?? false
        default: granted = false
        }
        guard granted else { return [] }
        return await Task.detached {
            var result: [ContactIndex.Contact] = []
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                        CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                for email in contact.emailAddresses {
                    result.append(.init(email: email.value as String,
                                        name: name.isEmpty ? (contact.organizationName.isEmpty ? nil : contact.organizationName) : name))
                }
            }
            return result
        }.value
    }
}
