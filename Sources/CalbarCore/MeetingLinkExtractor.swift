import Foundation

/// Finds the video link of an event, most reliable source first:
/// Google's structured conference data, the Meet link, then any known
/// provider URL in the location or the description.
public enum MeetingLinkExtractor {

    private static let urlTail = #"[^\s"'<>)]+"#

    private static let sources: [(String, MeetingLink.Provider)] = [
        // The lookahead rejects a longer code such as "abc-defg-hijk".
        (#"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}(?![a-z])"#, .meet),
        (#"https://([a-z0-9-]+\.)?zoom\.us/(j|my|w|s)/"# + urlTail, .zoom),
        // Old "/l/meetup-join/..." links and new "/meet/<id>?p=<code>" ones.
        (#"https://teams\.microsoft\.com/(l/meetup-join|meet)/"# + urlTail, .teams),
        (#"https://teams\.live\.com/meet/"# + urlTail, .teams),
        (#"https://[a-z0-9-]+\.webex\.com/"# + urlTail, .webex),
        (#"https://([a-z0-9-]+\.)?around\.co/"# + urlTail, .around),
        (#"https://whereby\.com/"# + urlTail, .whereby),
        (#"https://((ptb|canary)\.)?discord(app)?\.com/(channels|events)/"# + urlTail, .discord),
        (#"https://discord\.gg/"# + urlTail, .discord),
    ]

    private static let patterns: [(NSRegularExpression, MeetingLink.Provider)] = sources.map {
        (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1)
    }

    public static func extract(
        conferenceURIs: [String],
        hangoutLink: String?,
        location: String?,
        description: String?
    ) -> MeetingLink? {
        for uri in conferenceURIs {
            if let link = link(from: uri) { return link }
        }
        if let hangoutLink, let link = link(from: hangoutLink) { return link }
        for text in [location, description].compactMap({ $0 }) {
            if let link = firstLink(in: HTMLText.decodeEntities(text)) { return link }
        }
        return nil
    }

    private static func link(from string: String) -> MeetingLink? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host else { return nil }
        return MeetingLink(url: url, provider: .forHost(host))
    }

    /// Earliest provider URL in the text, whatever the provider.
    private static func firstLink(in text: String) -> MeetingLink? {
        let range = NSRange(text.startIndex..., in: text)
        var best: (location: Int, link: MeetingLink)?
        for (regex, provider) in patterns {
            guard let match = regex.firstMatch(in: text, range: range),
                  best == nil || match.range.location < best!.location,
                  let r = Range(match.range, in: text) else { continue }
            var raw = String(text[r])
            while let last = raw.last, ".,;:!?".contains(last) { raw.removeLast() }
            guard let url = URL(string: raw) else { continue }
            best = (match.range.location, MeetingLink(url: url, provider: provider))
        }
        return best?.link
    }
}
