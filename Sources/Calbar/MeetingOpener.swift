import AppKit
import CalbarCore

enum MeetingOpener {
    /// Opens the provider's app directly when it is installed, the web
    /// link otherwise.
    static func open(_ link: MeetingLink) {
        if let native = link.nativeURL,
           NSWorkspace.shared.urlForApplication(toOpen: native) != nil {
            NSWorkspace.shared.open(native)
        } else {
            NSWorkspace.shared.open(link.url)
        }
    }
}
