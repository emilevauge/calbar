import AppKit
import CalbarCore

enum MeetingOpener {
    /// Opens the provider's app directly when it is installed, the web
    /// link otherwise. A Discord "#channel" first goes through the
    /// channels listed in the settings.
    static func open(_ link: MeetingLink) {
        var link = link
        if link.channel != nil {
            let defaults = UserDefaults.standard
            let url = DiscordChannels.resolve(
                link,
                channels: DiscordChannels.parse(defaults.string(forKey: Prefs.discordChannelsKey) ?? ""),
                server: defaults.string(forKey: Prefs.discordServerKey))
            link = MeetingLink(url: url, provider: .discord)
        }
        if let native = link.nativeURL,
           NSWorkspace.shared.urlForApplication(toOpen: native) != nil {
            NSWorkspace.shared.open(native)
        } else {
            NSWorkspace.shared.open(link.url)
        }
    }
}
