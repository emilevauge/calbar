import Foundation

/// Strict percent-encoding: only RFC 3986 unreserved characters stay raw.
public enum FormEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    /// Query items ready for `URLComponents.percentEncodedQueryItems`.
    /// Plain `queryItems` leaves "+" raw, and Google reads a raw "+" as a
    /// space, which turns "emile+work@gmail.com" into "emile work@gmail.com".
    public static func percentEncoded(_ items: [URLQueryItem]) -> [URLQueryItem] {
        items.map { URLQueryItem(name: escape($0.name), value: $0.value.map(escape)) }
    }

    /// `application/x-www-form-urlencoded` body.
    public static func encode(_ pairs: [(String, String)]) -> Data {
        Data(pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&").utf8)
    }
}
