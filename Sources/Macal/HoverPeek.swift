import AppKit

/// Receives the tracking area events of the status item button.
private final class HoverTracker: NSResponder {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// Opens the popover in peek mode after the pointer rests on the status
/// item for `delay`. The tracking area covers the whole button, capsule
/// included. Closing on exit is the popover's job: the pointer may move
/// into it.
@MainActor
final class HoverPeek {
    private static let delay: Duration = .milliseconds(500)

    private let tracker = HoverTracker()
    private var pending: Task<Void, Never>?
    private var isInside = false
    /// Set on click: no peek until the pointer leaves the icon.
    private var suppressed = false

    /// Opens the peek; called once the pointer has rested on the icon.
    var peek: () -> Void = {}

    init() {
        tracker.onEnter = { [weak self] in self?.pointerEntered() }
        tracker.onExit = { [weak self] in self?.pointerExited() }
    }

    func attach(to button: NSStatusBarButton) {
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: tracker,
            userInfo: nil
        ))
    }

    /// Cancels a pending peek and keeps it off until the pointer leaves
    /// the icon. The hotkey also toggles the popover, with the pointer
    /// elsewhere: then there is no exit to clear the flag, so it is not set.
    func cancelForClick() {
        suppressed = isInside
        cancel()
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    private func pointerEntered() {
        isInside = true
        guard !suppressed else { return }
        cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.peek()
        }
    }

    private func pointerExited() {
        isInside = false
        suppressed = false
        cancel()
    }
}
