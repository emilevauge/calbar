import AppKit
import MacalCore
import UserNotifications

/// System notifications for a meeting, adapted from Claudette's
/// `SystemNotifications`: a standard banner when it enters its alert
/// window, and another when it starts, which replaces the first.
///
/// Inside a .app bundle it goes through `NotificationHub`: clickable, with
/// a Join action when the meeting has a link, and withdrawn when the alert
/// window ends or the meeting is dismissed. Without a bundle id (dev binary
/// from `swift build`) UNUserNotificationCenter crashes, so it falls back
/// to AppleScript `display notification`: no click, no action.
@MainActor
final class MeetingNotifier {
    private let store: EventStore
    private let join: JoinController
    private let hub = NotificationHub.shared

    /// Opens the popover expanded on the event with this id.
    var onOpenMacal: ((String) -> Void)?

    /// `occurrenceKey` of occurrences notified before the start, and of
    /// those notified at the start, with the end of their alert window.
    /// In memory only; a key is dropped once its window ends.
    private var fired: [String: Date] = [:]
    private var firedAtStart: [String: Date] = [:]

    private static let kind = "meeting"
    private static let categoryID = "meeting"
    private static let joinActionID = "join"
    private static let keyInfo = "occurrenceKey"
    private static let eventIDInfo = "eventID"

    init(store: EventStore, join: JoinController) {
        self.store = store
        self.join = join
    }

    /// Registers the Join category and the click handler with the hub.
    func start() {
        let joinAction = UNNotificationAction(identifier: Self.joinActionID, title: "Join", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [joinAction],
                                              intentIdentifiers: [], options: [])
        hub.register(kind: Self.kind, categories: [category]) { [weak self] action, info in
            // Body click and Join both join when there is a link; a body
            // click without a link opens the popover on the event.
            guard let key = info[Self.keyInfo],
                  action == UNNotificationDefaultActionIdentifier || action == Self.joinActionID else { return }
            self?.handle(key: key, eventID: info[Self.eventIDInfo])
        }
    }

    /// Called on every tick and data change: withdraws finished or dismissed
    /// notifications, then posts the ones that just became due.
    func update(now: Date) {
        let dismissed = join.dismissed
        for (key, end) in fired where end <= now || dismissed.contains(key) {
            fired.removeValue(forKey: key)
            hub.withdraw(id: Self.identifier(key))
        }
        for (key, end) in firedAtStart where end <= now || dismissed.contains(key) {
            firedAtStart.removeValue(forKey: key)
            hub.withdraw(id: Self.identifier(key, .starting))
        }
        guard Prefs.notifyBeforeMeetings else { return }
        let policy = Prefs.alertPolicy
        let skip = Set(fired.keys).union(firedAtStart.keys).union(dismissed)
        for event in NotificationPlanner.due(store.events, now: now, policy: policy, skip: skip) {
            fired[event.occurrenceKey] = NotificationPlanner.windowEnd(event, policy: policy)
            post(event, stage: .soon, now: now)
        }
        let skipAtStart = Set(firedAtStart.keys).union(dismissed)
        for event in NotificationPlanner.dueAtStart(store.events, now: now, policy: policy, skip: skipAtStart) {
            let key = event.occurrenceKey
            firedAtStart[key] = NotificationPlanner.windowEnd(event, policy: policy)
            // Its "In 5 min" banner is out of date: the new one replaces it.
            if fired.removeValue(forKey: key) != nil {
                hub.withdraw(id: Self.identifier(key))
            }
            post(event, stage: .starting, now: now)
        }
    }

    // MARK: posting

    private static func identifier(_ key: String, _ stage: NotificationPlanner.Stage = .soon) -> String {
        switch stage {
        case .soon: "macal.meeting.\(key)"
        case .starting: "macal.meeting.start.\(key)"
        }
    }

    private func post(_ event: CalendarEvent, stage: NotificationPlanner.Stage, now: Date) {
        let body = NotificationPlanner.body(event, now: now, calendar: .current)
        guard hub.isAvailable else {
            notifyViaAppleScript(title: event.title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        if event.meeting != nil { content.categoryIdentifier = Self.categoryID }
        content.userInfo = [Self.keyInfo: event.occurrenceKey, Self.eventIDInfo: event.id]
        hub.post(kind: Self.kind, id: Self.identifier(event.occurrenceKey, stage), content: content)
    }

    private func notifyViaAppleScript(title: String, body: String) {
        let source = """
        display notification "\(Self.escape(body))" with title "Macal" subtitle "\(Self.escape(title))"
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Macal: AppleScript notification failed: %@", error) }
    }

    /// Escapes a string for an AppleScript string literal, on one line.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: clicks

    private func handle(key: String, eventID: String?) {
        let event = store.events.first { $0.occurrenceKey == key }
        if let event, event.meeting != nil {
            join.join(event)
        } else if let id = event?.id ?? eventID {
            onOpenMacal?(id)
        }
    }
}
