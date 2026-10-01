import Foundation

/// Turns the HTML Google puts in event descriptions into readable text.
public enum HTMLText {

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "
    ]

    private static let entity = regex("&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);", caseInsensitive: false)
    // Groups: 1 double-quoted href, 2 single-quoted href, 3 label.
    private static let anchor = regex(
        #"<a\s[^>]*href\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>(.*?)</a>"#, dotAll: true
    )
    private static let lineBreak = regex(#"<br\b[^>]*>"#)
    private static let blockOpen = regex(#"<(p|div|h[1-6])(\s[^>]*)?>"#)
    private static let blockClose = regex(#"</(p|div|li|h[1-6])>"#)
    private static let listItem = regex(#"<li\b[^>]*>"#)
    // Only real tags and comments: "a < b" or "<https://...>" are text.
    private static let comment = regex(#"<!--.*?-->"#, dotAll: true)
    private static let tag = regex(#"</?[a-zA-Z][a-zA-Z0-9]*(\s[^>]*)?/?>"#)
    private static let trailingSpaces = regex(#"[ \t]+\n"#)
    private static let blankLines = regex(#"\n{3,}"#)

    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return replaceMatches(of: entity, in: s) { whole, groups in
            replacement(for: groups[0]) ?? whole
        }
    }

    public static func plainText(_ html: String) -> String {
        // Keep link targets visible: "label (url)", or just "url" when the
        // label already is the url. Raw text is emitted here and decoded
        // once at the end, so an encoded "&lt;b&gt;" label stays text.
        var s = replaceMatches(of: anchor, in: html) { _, groups in
            let rawHref = groups[0].isEmpty ? groups[1] : groups[0]
            let rawLabel = strip(groups[2]).trimmingCharacters(in: .whitespaces)
            let label = decodeEntities(rawLabel)
            return label.isEmpty || label == decodeEntities(rawHref) ? rawHref : "\(rawLabel) (\(rawHref))"
        }
        s = replace(s, lineBreak, "\n")
        s = replace(s, blockOpen, "\n")
        s = replace(s, blockClose, "\n")
        s = replace(s, listItem, "• ")
        s = strip(s)
        s = decodeEntities(s)
        s = replace(s, trailingSpaces, "\n")
        s = replace(s, blankLines, "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strip(_ s: String) -> String {
        replace(replace(s, comment, ""), tag, "")
    }

    private static func replacement(for name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return character(UInt32(name.dropFirst(2), radix: 16))
        }
        if name.hasPrefix("#") {
            return character(UInt32(name.dropFirst()))
        }
        return named[name.lowercased()]
    }

    /// Numeric entity value, refusing NUL and control characters other
    /// than newline and tab: those are left as entity text.
    private static func character(_ value: UInt32?) -> String? {
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        if scalar.properties.generalCategory == .control && scalar != "\n" && scalar != "\t" {
            return nil
        }
        return String(Character(scalar))
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = true, dotAll: Bool = false) -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func replace(_ s: String, _ regex: NSRegularExpression, _ template: String) -> String {
        regex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template
        )
    }

    /// Rebuilds `s`, passing each match (whole text, capture groups) to `transform`.
    private static func replaceMatches(
        of regex: NSRegularExpression,
        in s: String,
        _ transform: (String, [String]) -> String
    ) -> String {
        var result = ""
        var last = s.startIndex
        for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            let groups = (1..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
            }
            result += s[last..<whole.lowerBound]
            result += transform(String(s[whole]), groups)
            last = whole.upperBound
        }
        result += s[last...]
        return result
    }
}

/// Makes the URLs of a plain text clickable in a SwiftUI `Text`.
public enum Linkify {
    public static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}
