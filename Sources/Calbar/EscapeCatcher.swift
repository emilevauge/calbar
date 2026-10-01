import SwiftUI
import AppKit

/// `esc` for the event editor, caught before AppKit: in a text field the
/// field editor takes the key, and a popover closes on it, so SwiftUI's
/// key handlers never see it. The last editor shown in the key's window
/// gets it; a picker's own popover is another window and closes as usual.
@MainActor
final class EscapeCatcher {
    static let shared = EscapeCatcher()

    private struct Entry {
        let id: UUID
        weak var window: NSWindow?
        let handler: () -> Void
    }
    private var entries: [Entry] = []
    private var monitor: Any?

    func register(_ id: UUID, window: NSWindow, handler: @escaping () -> Void) {
        entries.removeAll { $0.id == id || $0.window == nil }
        entries.append(Entry(id: id, window: window, handler: handler))
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            nonisolated(unsafe) let key = event
            return MainActor.assumeIsolated {
                guard let entry = EscapeCatcher.shared.entries.last(where: { $0.window != nil && $0.window === key.window })
                else { return key }
                entry.handler()
                return nil
            }
        }
    }

    func unregister(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }
}

extension View {
    /// Runs `handler` on `esc` in this view's window, before any text
    /// field or popover handles it.
    func onEscape(_ handler: @escaping () -> Void) -> some View {
        modifier(EscapeModifier(handler: handler))
    }
}

private struct EscapeModifier: ViewModifier {
    let handler: () -> Void
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window in
                EscapeCatcher.shared.register(id, window: window, handler: handler)
            })
            .onDisappear { EscapeCatcher.shared.unregister(id) }
    }
}

/// Hands over the window it lands in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Reader(onWindow: onWindow) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? Reader)?.onWindow = onWindow
        if let window = view.window { onWindow(window) }
    }

    final class Reader: NSView {
        var onWindow: (NSWindow) -> Void
        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
