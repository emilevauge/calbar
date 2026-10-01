import AppKit
import SwiftUI
import Combine
import MacalCore

/// Non-activating panel for the hover card. It never takes the keyboard
/// and lets clicks through, like a tooltip.
final class HoverPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: HoverCard.width, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Receives the tracking area events of the status item button.
private final class HoverTracker: NSResponder {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// Shows the hover card under the status item after the pointer rests on
/// it for `delay`, and hides it on exit, click, or when the popover opens.
/// The tracking area covers the whole button, capsule included.
@MainActor
final class HoverCardController {
    private static let delay: Duration = .milliseconds(500)

    private let store: EventStore
    private let accounts: AccountStore
    private let tracker = HoverTracker()
    private weak var button: NSStatusBarButton?
    private var panel: HoverPanel?
    private var host: NSHostingView<HoverCard>?
    /// Measures the card: the panel's host has no sizing options, so its
    /// own fittingSize is zero.
    private var measurer: NSHostingController<HoverCard>?
    private var pending: Task<Void, Never>?
    private var updates: AnyCancellable?
    private var isInside = false
    /// Set on click: the card stays hidden until the pointer leaves the icon.
    private var suppressed = false

    /// Returns false while the card must not show, e.g. the popover is open.
    var canShow: () -> Bool = { true }
    /// Opens the popover on the current meeting instead of the card, and
    /// says whether it did: during a meeting the hover shows the real panel.
    var peek: () -> Bool = { false }
    /// The meeting the capsule joins at a given time, with its color.
    var dueState: (Date) -> (event: CalendarEvent, style: CapsuleStyle)? = { _ in nil }

    init(store: EventStore, accounts: AccountStore) {
        self.store = store
        self.accounts = accounts
        tracker.onEnter = { [weak self] in self?.pointerEntered() }
        tracker.onExit = { [weak self] in self?.pointerExited() }
    }

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: tracker,
            userInfo: nil
        ))
    }

    /// Hides the card and keeps it hidden until the pointer leaves the icon.
    /// The hotkey also toggles the popover, with the pointer elsewhere:
    /// then there is no exit to clear the flag, so it is not set.
    func dismissForClick() {
        suppressed = isInside
        hide()
    }

    func hide() {
        pending?.cancel()
        pending = nil
        updates = nil
        panel?.orderOut(nil)
    }

    /// Follows the icon when its width changes with the countdown.
    func repositionIfVisible() {
        if panel?.isVisible == true { layout() }
    }

    private func pointerEntered() {
        isInside = true
        guard !suppressed else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    private func pointerExited() {
        isInside = false
        suppressed = false
        hide()
    }

    private func show() {
        pending = nil
        guard canShow(), button?.window != nil else { return }
        if peek() { return }
        let panel = self.panel ?? HoverPanel()
        self.panel = panel
        render()
        panel.orderFrontRegardless()
        // Live content while visible. `receive(on:)` lets @Published finish
        // its willSet before the stores are read.
        updates = Publishers.CombineLatest3(store.$now, store.$rawEvents, accounts.$accounts)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
    }

    private func render() {
        guard let panel else { return }
        let card = HoverCard(
            events: store.events,
            now: store.now,
            needsReconnect: accounts.needsAttention,
            due: dueState(store.now)
        )
        if let host {
            host.rootView = card
        } else {
            let host = NSHostingView(rootView: card)
            // The controller sizes the panel itself, so it can keep the
            // card anchored under the icon when its height changes.
            host.sizingOptions = []
            panel.contentView = host
            self.host = host
        }
        layout()
    }

    /// Just below the item, kept inside the visible frame. Aligned with the
    /// capsule's left edge, where the title starts; centered on the plain
    /// glyph.
    private func layout() {
        guard let panel, let host, let button, let window = button.window else { return }
        let measurer = self.measurer ?? NSHostingController(rootView: host.rootView)
        measurer.rootView = host.rootView
        self.measurer = measurer
        let fitted = measurer.sizeThatFits(in: CGSize(width: HoverCard.width, height: 10_000))
        let size = CGSize(width: ceil(fitted.width), height: ceil(fitted.height))
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? icon
        let margin: CGFloat = 8
        var x = icon.width > 40 ? icon.minX : icon.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        let y = max(icon.minY - 6 - size.height, visible.minY + margin)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        host.frame = NSRect(origin: .zero, size: size)
    }
}
