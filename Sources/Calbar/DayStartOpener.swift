import AppKit
import CalbarCore

/// Opens the popover at the first user activity of the day (launch, wake,
/// unlock, return to the session) when a meeting is left today. At most
/// once per calendar day: the day is marked only once the popover opened.
/// Not before 06:00: an earlier trigger arms a timer for 06:00, so a user
/// already at the desk then still gets the popover.
///
/// The decision waits for a refresh that completed after the trigger, so
/// it uses today's events rather than a cache from yesterday. After a
/// wake the network often takes a few seconds: past `freshDataTimeout` it
/// decides on the cached events.
@MainActor
final class DayStartOpener {
    private let store: EventStore
    private let isPopoverShown: () -> Bool
    private let open: () -> Void

    /// Upper bound on the wait for fresh events.
    private let freshDataTimeout: TimeInterval = 60
    /// Between the decision and the opening, so the desktop is visible and
    /// the status item is in place.
    private let openDelay: Duration = .milliseconds(1500)
    /// While offline, how often the wait asks for another refresh: the
    /// regular poll may be minutes away.
    private let offlineRetry: TimeInterval = 10

    /// The check in progress. A trigger arriving meanwhile joins it.
    private var pending: Task<Void, Never>?
    /// Fires at today's day start after an earlier trigger.
    private var dayStartTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(store: EventStore, isPopoverShown: @escaping () -> Bool, open: @escaping () -> Void) {
        self.store = store
        self.isPopoverShown = isPopoverShown
        self.open = open
    }

    /// Watches wake, unlock and session switches, and runs the launch check.
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let refreshes = name != NSWorkspace.didWakeNotification
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The store already refreshes on wake.
                MainActor.assumeIsolated { self?.trigger(requestRefresh: refreshes) }
            })
        }
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trigger(requestRefresh: true) }
        })
        // The store's first refresh starts with the app.
        trigger(requestRefresh: false)
    }

    /// `requestRefresh`: nothing else refreshes the store for this trigger.
    private func trigger(requestRefresh: Bool) {
        guard Prefs.openPanelAtDayStart, !openedToday(), pending == nil else { return }
        if DayStartPolicy.isBeforeDayStart(Date(), calendar: .current) {
            armDayStartTimer()
            return
        }
        let since = Date()
        if requestRefresh {
            Task { await store.refresh() }
        }
        pending = Task { [weak self] in
            await self?.run(since: since)
            self?.pending = nil
        }
    }

    /// One timer at a time; a later early trigger keeps the one in place.
    private func armDayStartTimer() {
        guard dayStartTimer == nil,
              let start = DayStartPolicy.dayStart(for: Date(), calendar: .current) else { return }
        let timer = Timer(fire: start, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dayStartTimer = nil
                self?.trigger(requestRefresh: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayStartTimer = timer
    }

    private func openedToday() -> Bool {
        Prefs.lastDayStartOpen == DayStartPolicy.dayKey(for: Date(), calendar: .current)
    }

    private func run(since: Date) async {
        await waitForFreshEvents(since: since)
        guard shouldOpen() else { return }
        try? await Task.sleep(for: openDelay)
        // Checked again: the user may have opened it, or locked the screen.
        guard shouldOpen() else { return }
        open()
        if isPopoverShown() {
            Prefs.lastDayStartOpen = DayStartPolicy.dayKey(for: Date(), calendar: .current)
            NSLog("Calbar: popover opened at day start")
        }
    }

    /// Returns once a refresh reached Google after `since`, or at the timeout.
    private func waitForFreshEvents(since: Date) async {
        let deadline = since.addingTimeInterval(freshDataTimeout)
        var lastRetry = since
        while Date() < deadline {
            if let fetched = store.lastFetch, fetched >= since { return }
            if store.isOffline, !store.isRefreshing, Date().timeIntervalSince(lastRetry) >= offlineRetry {
                lastRetry = Date()
                Task { await store.refresh() }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        NSLog("Calbar: day start check uses cached events")
    }

    private func shouldOpen() -> Bool {
        // A locked screen hides the popover: the unlock triggers a new check.
        guard !Session.isScreenLocked, !isPopoverShown() else { return false }
        return DayStartPolicy.shouldOpen(
            lastOpenedDay: Prefs.lastDayStartOpen,
            now: Date(),
            calendar: .current,
            remainingMeetings: DayStartPolicy.remainingMeetings(
                in: DayAgenda.build(from: store.events, now: Date(), calendar: .current)),
            enabled: Prefs.openPanelAtDayStart
        )
    }
}
