import Foundation

/// A copy of an event gets its own Meet or Zoom meeting: the old one's
/// link and invitation lines come out of its place and description.
public enum MeetingCleanup {
    /// Providers whose meeting a copy recreates.
    public static func regenerates(_ provider: MeetingLink.Provider) -> Bool {
        provider == .meet || provider == .zoom
    }

    /// `location` without the links of `provider`, and the separators
    /// left around them.
    public static func location(_ location: String, removing provider: MeetingLink.Provider) -> String {
        var text = location
        for url in links(in: location, provider: provider) { text = text.replacingOccurrences(of: url, with: "") }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;|-\n\t"))
    }

    /// `notes` without the lines of `provider`'s invitation: its links,
    /// "Join Zoom Meeting", the meeting id and passcode, Meet's phone lines.
    public static func notes(_ notes: String, removing provider: MeetingLink.Provider) -> String {
        let prefixes: [String] = switch provider {
        case .zoom: ["join zoom meeting", "meeting id:", "passcode:", "password:", "one tap mobile",
                     "join by sip", "join by h.323", "dial by your location", "find your local number"]
        case .meet: ["join with google meet", "join by phone", "more phone numbers", "or dial:", "pin:",
                     "learn more about meet"]
        default: []
        }
        var kept: [String] = []
        for line in notes.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if !links(in: line, provider: provider).isEmpty { continue }
            if prefixes.contains(where: { trimmed.hasPrefix($0) }) { continue }
            // Two blank lines in a row where the invitation was.
            if trimmed.isEmpty, kept.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? true { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func links(in text: String, provider: MeetingLink.Provider) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, let host = url.host, MeetingLink.Provider.forHost(host) == provider,
                  let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }
}
