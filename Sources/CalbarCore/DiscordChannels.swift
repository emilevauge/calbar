import Foundation

/// Discord channels named in event locations ("#standup"). A channel's
/// link holds the server's and the channel's ids, which its name alone
/// does not give, so the user lists them in the settings, one per line:
/// "#standup https://discord.com/channels/<server>/<channel>". A channel
/// not listed opens the server, or Discord.
public enum DiscordChannels {
    public static let home = URL(string: "https://discord.com/app")!

    /// "#name link" lines to links by lowercased name; other lines are
    /// skipped.
    public static func parse(_ text: String) -> [String: URL] {
        var result: [String: URL] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2,
                  let url = URL(string: parts[parts.count - 1]), url.host.map(isDiscord) == true else { continue }
            let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
            if !name.isEmpty { result[name] = url }
        }
        return result
    }

    /// The https link to open for `link`: its own, or for a named channel
    /// the listed one, else the server of `server` (any link into it),
    /// else Discord's home.
    public static func resolve(_ link: MeetingLink, channels: [String: URL], server: String?) -> URL {
        guard let channel = link.channel else { return link.url }
        if let url = channels[channel.lowercased()] { return url }
        if let server, let guild = guildID(server) {
            return URL(string: "https://discord.com/channels/\(guild)")!
        }
        return link.url
    }

    /// "https://discord.com/channels/<server>/..." to "<server>".
    static func guildID(_ text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.host.map(isDiscord) == true else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "channels", parts[2].allSatisfy(\.isNumber) else { return nil }
        return parts[2]
    }

    /// The desktop app's link for a channel or event link
    /// ("discord://-/channels/<server>/<channel>"), and for Discord's home;
    /// nil for an invite, which only the web page accepts.
    static func appURL(for url: URL) -> URL? {
        guard url.host.map(isDiscord) == true, url.host != "discord.gg" else { return nil }
        if url.path == "/app" { return URL(string: "discord://-/channels/@me") }
        guard url.path.hasPrefix("/channels/") || url.path.hasPrefix("/events/") else { return nil }
        return URL(string: "discord://-" + url.path)
    }

    private static func isDiscord(_ host: String) -> Bool {
        MeetingLink.Provider.forHost(host) == .discord
    }
}
