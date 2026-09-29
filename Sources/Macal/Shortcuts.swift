import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to show / hide the Macal popover.
    static let toggleMacal = Self(
        "toggleMacal",
        default: .init(.m, modifiers: [.control, .option])
    )
}
