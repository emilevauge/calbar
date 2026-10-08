import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts
import CalbarCore

/// App controller: status item, popover, account actions. AppKit
/// NSStatusItem + NSPopover rather than MenuBarExtra, to open the popover
/// from code (hotkey, "Open Calbar"), like Claudette. A single status item:
/// while a meeting with a link is due, its image becomes a capsule that
/// holds the join link and the calendar glyph.
@MainActor
final class AppDelegate: NSObject, ObservableObject {
    static let shared = AppDelegate()

    let accounts: AccountStore
    /// Nil until a Google OAuth client is imported (or bundled in a dev
    /// build). Replaced in place when the user imports another one.
    @Published private(set) var auth: GoogleAuth?
    let store: EventStore
    let join: JoinController
    let peeker: MeetingPeeker
    let hoverPeek = HoverPeek()

    /// Last sign-in failure, shown in the settings panel.
    @Published var authError: String?
    /// Last failed OAuth client import, shown next to the import button.
    @Published private(set) var clientImportError: String?
    /// A browser sign-in is waiting for Google's redirect.
    @Published private(set) var isSigningIn = false
    /// Bumped every time the popover closes, so it opens on today again.
    @Published private(set) var popoverCloseCount = 0
    /// The popover opened on hover during a meeting: it shows only the
    /// current meeting until a click expands it to the whole day.
    @Published private(set) var isPeeking = false
    /// Closes the peeking popover once the pointer has left it and the icon.
    private var peekWatch: Task<Void, Never>?
    /// Guest suggestions for the editor.
    let contacts: ContactBook
    /// Zoom meetings for new events.
    let zoom = ZoomAuth()

    private var signInTask: Task<Void, Never>?
    /// Tells a finished sign-in whether a newer one replaced it.
    private var signInGeneration = 0

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastRender: Render?
    /// Redraws when the menu bar turns light or dark (wallpaper, mode).
    private var appearanceObservation: NSKeyValueObservation?
    /// Width from the image's left edge where a click joins; 0 without capsule.
    private var joinZoneWidth: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    private var dayStart: DayStartOpener?

    private override init() {
        // Before any store reads its data.
        LegacyMacal.migrate()
        Prefs.register()
        let accounts = AccountStore()
        let client = OAuthConfig.load()
        if let client {
            Self.adopt(client, accounts: accounts)
        }
        let auth = client.map { Self.makeAuth($0, accounts: accounts) }
        self.accounts = accounts
        self.auth = auth
        let store = EventStore(accounts: accounts, auth: auth)
        self.store = store
        let join = JoinController(store: store)
        self.join = join
        self.peeker = MeetingPeeker(store: store, join: join)
        self.contacts = ContactBook(store: store, accounts: accounts)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didFinishLaunching(_:)),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
    }

    @objc private func didFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppIcon.install()
        LaunchAgent.syncIfNeeded()
        LegacyMacal.trashOldApp()
        NotificationHub.shared.start()
        UpdateChecker.startPeriodicCheck()

        setupStatusItem()
        setupPopover()
        join.onOpenCalbar = { [weak self] event in
            self?.store.requestedEventID = event.id
            self?.showPopover()
        }
        join.onChange = { [weak self] in self?.refreshIndicators() }
        peeker.show = { [weak self] event in self?.peek(on: event, for: MeetingPeeker.duration) ?? false }
        observe()
        store.start()
        let dayStart = DayStartOpener(
            store: store,
            isPopoverShown: { [weak self] in self?.popover?.isShown == true },
            open: { [weak self] in self?.showPopover() }
        )
        dayStart.start()
        self.dayStart = dayStart

        KeyboardShortcuts.onKeyDown(for: .toggleCalbar) { [weak self] in
            self?.togglePopover(nil)
        }
    }

    // MARK: status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            // No plain toolTip: hovering opens the popover in peek mode.
            button.setAccessibilityLabel("Calbar")
            hoverPeek.attach(to: button)
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refreshIndicators() }
            }
        }
        statusItem = item
        hoverPeek.peek = { [weak self] in self?.peek() }
        refreshIndicators()
    }

    private func setupPopover() {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.contentSize = NSSize(width: 380, height: 480)
        // Fits the content, and animates with it when it changes size.
        let host = PopoverHost(rootView: MenuView(store: store, accounts: accounts))
        host.popover = p
        p.contentViewController = host
        p.contentSize = host.fittingSize
        popover = p
        // Covers every way it closes: click outside, esc, joining a meeting.
        NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: p, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopWatchingOutsideClicks()
                self?.peekWatch?.cancel()
                self?.isPeeking = false
                self?.peekTarget = nil
                self?.popoverCloseCount += 1
                self?.store.popoverDidClose()
            }
        }
    }

    private func observe() {
        // `receive(on:)` defers to the next main queue pass: @Published fires
        // in willSet, so reading the stores synchronously would see old values.
        // DispatchQueue rather than RunLoop.main, which pauses while a menu
        // or a drag tracks events.
        Publishers.CombineLatest3(store.$now, store.$rawEvents, accounts.$accounts)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIndicators() }
            .store(in: &cancellables)
    }

    /// What the item draws: the redraw happens only when this changes.
    private struct Render: Equatable {
        let badge: MenuBarBadge
        let join: StatusItemImage.Join?
        /// The glowing in-meeting page is not a template: its ink follows
        /// the menu bar.
        let dark: Bool
        /// A meeting is running: the glow stays even when the badge shows
        /// the next meeting's countdown.
        let onAir: Bool
    }

    private func indicatorState(now: Date) -> (badge: MenuBarBadge, queue: JoinQueue, style: CapsuleStyle?) {
        let badge = MenuBarBadge.compute(
            events: store.events,
            now: now,
            leadTime: Prefs.alertPolicy.leadTime,
            calendar: .current,
            needsAttention: accounts.needsAttention,
            due: join.due(now: now)
        )
        let queue = join.queue(now: now)
        return (badge, queue, CapsuleStyle.make(badge: badge, primary: queue.primary, now: now))
    }

    private func refreshIndicators() {
        // After the icon: a peek opened in the same tick as the capsule
        // appears must anchor on the new, wider icon.
        defer { peeker.update(now: store.now) }
        let state = indicatorState(now: store.now)
        var capsule: StatusItemImage.Join?
        if let event = state.queue.primary, let style = state.style {
            capsule = StatusItemImage.Join(title: event.title, extraCount: state.queue.extraCount, style: style)
        }
        guard let button = statusItem?.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let onAir = NextMeeting.ongoing(events: store.events, now: store.now) != nil
        let render = Render(badge: state.badge, join: capsule, dark: dark, onAir: onAir)
        guard render != lastRender else { return }
        lastRender = render
        let (image, zone) = StatusItemImage.make(badge: render.badge, join: render.join, dark: render.dark, onAir: render.onAir)
        let widthChanged = button.image?.size.width != image.size.width
        button.image = image
        joinZoneWidth = zone
        button.setAccessibilityLabel(capsule.map { "Calbar, Join \($0.title)" } ?? "Calbar")
        // The icon may have changed width under an open popover: anchor it
        // again once the menu bar has laid the item out.
        guard widthChanged else { return }
        DispatchQueue.main.async { [weak self] in
            guard let popover = self?.popover, popover.isShown, let button = self?.statusItem?.button else { return }
            popover.positioningRect = button.bounds
        }
    }

    // MARK: clicks

    /// Left click on the title part of the capsule joins, elsewhere it
    /// toggles the popover. Right click or control-click opens the menu of
    /// due meetings, or toggles the popover when nothing is due.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        // The state may be stale by up to one tick: recompute before acting.
        let now = Date()
        if wantsMenu {
            if let menu = join.makeMenu(now: now) {
                showMenu(menu)
            } else {
                togglePopover(sender)
            }
            return
        }
        if let event, let primary = join.queue(now: now).primary, joinZoneWidth > 0,
           let image = sender.image {
            // The button centers its image: measure from the image's edge.
            let x = sender.convert(event.locationInWindow, from: nil).x
                - (sender.bounds.width - image.size.width) / 2
            if x < joinZoneWidth {
                hoverPeek.cancelForClick()
                join.join(primary)
                return
            }
        }
        togglePopover(sender)
    }

    /// Attached to the item only while it tracks, so a left click keeps
    /// going to `statusItemClicked(_:)`.
    private func showMenu(_ menu: NSMenu) {
        guard let statusItem else { return }
        hoverPeek.cancelForClick()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: popover

    @objc func togglePopover(_ sender: Any?) {
        hoverPeek.cancelForClick()
        if isPeeking {
            expandPeek()
        } else if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        if isPeeking { return expandPeek() }
        guard let popover, let button = statusItem?.button, !popover.isShown else { return }
        popover.behavior = .transient
        hoverPeek.cancel()
        NSApp.activate(ignoringOtherApps: true)
        present(popover, from: button) {
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Shows the popover at the size of what it is about to display, not
    /// the size it had when it last closed (a peek, or the full day). The
    /// hop lets SwiftUI apply the mode change before it is measured.
    private func present(_ popover: NSPopover, from button: NSStatusBarButton, then: @escaping () -> Void = {}) {
        DispatchQueue.main.async { [weak self] in
            guard !popover.isShown else { return }
            // The icon may have left the screen during the hop.
            if self?.isPeeking == true, !Self.isOnScreen(button) {
                self?.isPeeking = false
                return
            }
            (popover.contentViewController as? PopoverHost<MenuView>)?.fitPopover()
            let wasActive = NSApp.isActive
            let peeking = self?.isPeeking == true
            // A transient popover closes when Calbar deactivates; a peek is
            // closed by its own timer and the outside clicks instead.
            popover.behavior = peeking ? .applicationDefined : .transient
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self?.watchOutsideClicks()
            // Showing a popover activates the app, and the keyboard would
            // leave the app in use: a peek gives it back once shown.
            if peeking && !wasActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard self?.isPeeking == true else { return }
                    NSApp.deactivate()
                }
            }
            then()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    /// For the hour grid: the calendars new events may go to, guest
    /// suggestions, and creating.
    var composer: EventComposer {
        EventComposer(calendars: accounts.writableCalendars, contacts: contacts, zoom: zoom, create: { [store] event, email in
            try await store.create(event, in: email)
        }, update: { [store] original, draft, notesText, scope in
            try await store.update(original, to: draft, notesText: notesText, scope: scope)
        })
    }

    /// The menu bar icon is on a screen, in view: not in a hidden menu bar
    /// (an app in full screen) nor on a display or space out of sight. A
    /// popover shown from an icon out of view lands at the bottom left of
    /// the screen.
    static func isOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, window.isVisible, window.occlusionState.contains(.visible) else { return false }
        let frame = window.frame
        guard frame.width > 0, frame.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
        else { return false }
        // The menu bar is at the top of its screen.
        return frame.midY > screen.frame.midY
    }

    /// The meeting a timed peek was opened on; nil for a hover peek.
    private var peekTarget: String?

    /// Opens the popover on one meeting alone (`peekEvent`), without
    /// taking the focus from the active app.
    func peek() {
        guard let popover, let button = statusItem?.button, !popover.isShown, Self.isOnScreen(button) else { return }
        peekTarget = nil
        isPeeking = true
        present(popover, from: button)
        watchPeek(until: nil)
    }

    /// Opens a peek on `event` that closes by itself after `duration`,
    /// unless the pointer is on it then. A peek already showing moves to
    /// `event`. False while the full popover is open.
    func peek(on event: CalendarEvent, for duration: TimeInterval) -> Bool {
        guard let popover, let button = statusItem?.button else { return false }
        if popover.isShown && !isPeeking { return false }
        // Not now: the next tick tries again, until the alert window ends.
        guard Self.isOnScreen(button) else { return false }
        peekTarget = event.occurrenceKey
        if Prefs.soundBeforeMeetings {
            NSSound(named: "Glass")?.play()
        }
        if !popover.isShown {
            isPeeking = true
            present(popover, from: button)
        }
        watchPeek(until: Date().addingTimeInterval(duration))
        return true
    }

    /// The meeting a peek shows: the one it was opened on, else the one the
    /// join capsule is about, else the ongoing one, else the next of
    /// today. Nil once the day is over.
    func peekEvent(now: Date) -> CalendarEvent? {
        if let peekTarget, let event = store.events.first(where: { $0.occurrenceKey == peekTarget }) {
            return event
        }
        return join.queue(now: now).primary ?? NextMeeting.focus(events: store.events, now: now, calendar: .current)
    }

    /// Clicks in other apps. A transient popover closes on a click outside
    /// only while Calbar is the active app; a peek, or a popover left
    /// behind by a menu, is not, and would stay open.
    private var outsideClicks: Any?

    private func watchOutsideClicks() {
        guard outsideClicks == nil else { return }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.popover?.isShown == true else { return }
                // A click on the menu bar icon is the icon's to handle.
                if let frame = self.statusItem?.button?.window?.frame, frame.contains(NSEvent.mouseLocation) { return }
                self.closePopover()
            }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    /// Grows the peeking popover to the whole day and gives it the keyboard.
    func expandPeek() {
        guard isPeeking else { return }
        peekWatch?.cancel()
        // Same curve as the popover frame, which `PopoverHost` animates.
        withAnimation(Motion.resize) {
            isPeeking = false
        }
        popover?.behavior = .transient
        NSApp.activate(ignoringOtherApps: true)
        popover?.contentViewController?.view.window?.makeKey()
    }

    /// Polls the pointer: a tracking area on the popover would miss the
    /// gap between it and the icon. A hover peek closes after 0.4 s
    /// outside both; a timed one (`deadline`) stays until then, and once
    /// the pointer has been on it, follows the hover rule.
    private func watchPeek(until deadline: Date?) {
        peekWatch?.cancel()
        peekWatch = Task { [weak self] in
            var outsideSince: Date?
            var deadline = deadline
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.isPeeking, self.popover?.isShown == true else { return }
                let pointer = NSEvent.mouseLocation
                let frames = [self.statusItem?.button?.window?.frame,
                              self.popover?.contentViewController?.view.window?.frame].compactMap { $0 }
                if frames.contains(where: { $0.insetBy(dx: -6, dy: -6).contains(pointer) }) {
                    outsideSince = nil
                    deadline = nil
                } else if let until = deadline {
                    if Date() >= until {
                        self.closePopover()
                        return
                    }
                } else if let since = outsideSince {
                    if Date().timeIntervalSince(since) > 0.4 {
                        self.closePopover()
                        return
                    }
                } else {
                    outsideSince = Date()
                }
            }
        }
    }

    // MARK: accounts

    /// Sign in a new account, or reconnect an existing one via `loginHint`.
    /// Starting a sign-in cancels the one in progress.
    func addAccount(loginHint: String? = nil) {
        guard let auth else {
            authError = "Import a Google OAuth client first."
            return
        }
        signInTask?.cancel()
        signInGeneration += 1
        let generation = signInGeneration
        authError = nil
        isSigningIn = true
        signInTask = Task {
            let result: Result<(email: String, scopes: [String]?), Error>
            do {
                result = .success(try await auth.signIn(loginHint: loginHint))
            } catch {
                result = .failure(error)
            }
            // A newer sign-in replaced this one: it owns the state now.
            guard generation == signInGeneration else { return }
            isSigningIn = false
            signInTask = nil
            switch result {
            case .success(let signedIn):
                accounts.upsert(email: signedIn.email, grantedScopes: signedIn.scopes)
                await store.refresh()
            case .failure(let error):
                NSLog("Calbar: sign-in failed: %@", "\(error)")
                // Cancelled by the user: no message. Timeout: "Sign-in cancelled."
                if !Task.isCancelled { authError = describe(error) }
            }
        }
    }

    // MARK: OAuth client

    /// Asks for the JSON file of a Google "Desktop app" OAuth client,
    /// validates it, keeps a private copy and starts using it right away.
    func importOAuthClient() {
        // After the current event: the button may sit in a popover that
        // closes when the panel takes focus.
        DispatchQueue.main.async { [weak self] in
            self?.runImportPanel()
        }
    }

    private func runImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import a Google OAuth client"
        panel.message = "Choose the JSON file of a Desktop app client downloaded from Google Cloud Console."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let client = try OAuthConfig.importFile(at: url)
            clientImportError = nil
            use(client)
            NSLog("Calbar: OAuth client imported")
        } catch {
            NSLog("Calbar: OAuth client import failed: %@", "\(type(of: error))")
            clientImportError = error is DecodingError || error is OAuthClientFile.InvalidClient
                ? "This file is not a Google OAuth client for a Desktop app."
                : "Could not import this file."
        }
    }

    /// Switches to `client` without a restart. Accounts signed in with a
    /// different client are marked for reconnection.
    private func use(_ client: OAuthClient) {
        guard auth?.client != client else { return }
        Self.adopt(client, accounts: accounts)
        signInTask?.cancel()
        let auth = Self.makeAuth(client, accounts: accounts)
        self.auth = auth
        store.auth = auth
        Task { await store.refresh() }
    }

    /// A `GoogleAuth` that keeps each account's granted scopes up to date.
    private static func makeAuth(_ client: OAuthClient, accounts: AccountStore) -> GoogleAuth {
        let auth = GoogleAuth(client: client)
        auth.onGrantedScopes = { [weak accounts] email, scopes in
            accounts?.setGrantedScopes(scopes, email: email)
        }
        return auth
    }

    /// Records `client` as the current one, marking the saved accounts for
    /// reconnection when they were signed in with another client.
    private static func adopt(_ client: OAuthClient, accounts: AccountStore) {
        if OAuthClientFile.accountsMustReconnect(
            knownClientID: OAuthConfig.knownClientID, newClientID: client.clientID,
            hasAccounts: !accounts.accounts.isEmpty
        ) {
            NSLog("Calbar: OAuth client changed, accounts must reconnect")
            for account in accounts.accounts {
                accounts.setNeedsReconnect(true, email: account.email)
            }
        }
        OAuthConfig.knownClientID = client.clientID
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func removeAccount(_ email: String) async {
        await auth?.signOut(email)
        accounts.remove(email)
        store.forget(email)
    }
}
