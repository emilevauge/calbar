import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to show / hide the Calbar popover.
    static let toggleCalbar = Self(
        "toggleCalbar",
        default: .init(.m, modifiers: [.control, .option])
    )
}
