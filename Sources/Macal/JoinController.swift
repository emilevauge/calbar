import AppKit
import MacalCore

/// Meetings the Macal item offers to join, from `leadTime` before a meeting
/// with a video link until `lingerAfterStart` after its start. Keeps the
/// dismissed set and builds the right-click menu; the status item itself
/// belongs to `AppDelegate`.
@MainActor
final class JoinController {
    private let store: EventStore
    /// `occurrenceKey` of alerts the user dismissed with "Dismiss". In memory
    /// only: a relaunch during the alert window shows them again.
    private(set) var dismissed: Set<String> = []

    /// Opens the popover expanded on the event.
    var onOpenMacal: ((CalendarEvent) -> Void)?
    /// Called after the dismissed set changes, so the icon follows.
    var onChange: (() -> Void)?

    init(store: EventStore) {
        self.store = store
    }

    /// Current alerts, dismissed ones left out, with or without a link.
    func due(now: Date) -> [CalendarEvent] {
        AlertPlanner.due(store.events, now: now, policy: Prefs.alertPolicy, dismissed: dismissed)
    }

    /// Due meetings with a link, earliest first.
    func queue(now: Date) -> JoinQueue {
        JoinQueue(events: store.events, now: now, policy: Prefs.alertPolicy, dismissed: dismissed)
    }

    func join(_ event: CalendarEvent) {
        // Joining does not dismiss: the capsule stays until the linger
        // ends, so the link is still there to rejoin.
        if let meeting = event.meeting { MeetingOpener.open(meeting) }
    }

    func dismiss(_ event: CalendarEvent) {
        dismissed.insert(event.occurrenceKey)
        onChange?()
    }

    /// Per due meeting: header, Join, attachments, Dismiss; then
    /// Open Macal. Nil when nothing is due.
    func makeMenu(now: Date) -> NSMenu? {
        let queue = queue(now: now)
        guard let first = queue.primary else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, event) in queue.meetings.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: "\(event.title) · \(AgendaFormat.timeRange(event, calendar: .current))"))
            menu.addItem(ActionMenuItem("Join", symbol: "video.fill") { [weak self] in
                self?.join(event)
            })
            for file in event.attachments {
                menu.addItem(ActionMenuItem(file.title, symbol: file.symbolName) {
                    NSWorkspace.shared.open(file.url)
                })
            }
            menu.addItem(ActionMenuItem("Dismiss", symbol: "xmark") { [weak self] in
                self?.dismiss(event)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Open Macal", symbol: nil) { [weak self] in
            // After the menu has closed, or the transient popover
            // would see the menu's click and close at once.
            DispatchQueue.main.async { self?.onOpenMacal?(first) }
        })
        return menu
    }
}

/// Menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String?, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() { handler() }
}
