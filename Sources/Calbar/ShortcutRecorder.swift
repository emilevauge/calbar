import SwiftUI
import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// Records the global shortcut, stored through KeyboardShortcuts.
///
/// Replaces `KeyboardShortcuts.Recorder`: its placeholder text reads the
/// package's localizations through the SwiftPM `Bundle.module` accessor,
/// which only looks next to the executable's bundle root and in the build
/// folder, and aborts the process when neither exists. That is the case in
/// the released app on any other Mac, so opening the settings would crash.
struct ShortcutRecorder: View {
    let title: String
    let name: KeyboardShortcuts.Name

    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type the shortcut…" : shortcut.map(Self.label) ?? "Record shortcut")
                    .frame(minWidth: 100)
            }
            .help(recording ? "Esc to cancel, Delete to clear" : "Click to record a new shortcut")
            if shortcut != nil, !recording {
                Button {
                    save(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the shortcut")
            }
        }
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        recording = true
        // The current shortcut must not toggle the popover while typing it.
        KeyboardShortcuts.isEnabled = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        KeyboardShortcuts.isEnabled = true
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)
        if modifiers.isEmpty {
            switch keyCode {
            case kVK_Escape:
                stop()
                return
            case kVK_Delete, kVK_ForwardDelete:
                save(nil)
                stop()
                return
            default:
                break
            }
        }
        // A global shortcut needs a modifier besides Shift, or a function key.
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9,
                            kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17,
                            kVK_F18, kVK_F19, kVK_F20]
        guard !modifiers.subtracting(.shift).isEmpty || functionKeys.contains(keyCode),
              let recorded = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return
        }
        save(recorded)
        stop()
    }

    private func save(_ value: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(value, for: name)
        shortcut = value
    }

    /// "⌃⌥M". Space is spelled out here: the package's own description
    /// looks the word up in its resource bundle.
    private static func label(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        guard shortcut.key == .space else { return shortcut.description }
        let m = shortcut.modifiers
        var symbols = ""
        if m.contains(.control) { symbols += "⌃" }
        if m.contains(.option) { symbols += "⌥" }
        if m.contains(.shift) { symbols += "⇧" }
        if m.contains(.command) { symbols += "⌘" }
        return symbols + "Space"
    }
}
