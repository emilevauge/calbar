import Foundation

/// Links to the Google Calendar web app.
public enum GoogleCalendarWeb {
    /// Calendar home, pinned to `email` when given so the browser does not
    /// open whichever Google account is signed in first.
    public static func home(authuser email: String?) -> URL {
        var c = URLComponents(string: "https://calendar.google.com/calendar/r")!
        if let email, !email.isEmpty {
            c.percentEncodedQueryItems = [authuserItem(email)]
        }
        return c.url!
    }

    /// `authuser=<email>` with the email fully percent-encoded. A raw `+`
    /// in a query would be read back as a space, so plain `URLQueryItem`
    /// encoding is not enough for addresses like `me+cal@example.com`.
    static func authuserItem(_ email: String) -> URLQueryItem {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = email.addingPercentEncoding(withAllowedCharacters: allowed) ?? email
        return URLQueryItem(name: "authuser", value: encoded)
    }
}
