import SwiftUI
import MacalCore

/// Guests as overlapping initials, "+N" past `limit`.
struct AvatarStack: View {
    let attendees: [Attendee]
    var limit = 5

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(attendees.prefix(limit).enumerated()), id: \.offset) { _, attendee in
                Avatar(person: attendee.person, response: attendee.response)
            }
            if attendees.count > limit {
                Text("+\(attendees.count - limit)")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Avatar.size, height: Avatar.size)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Avatar.ring)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Initials on a color derived from the email, so a person keeps the same
/// color everywhere. Declined guests are faded.
struct Avatar: View {
    static let size: CGFloat = 20
    let person: Person
    let response: ResponseStatus

    var body: some View {
        Text(Self.initials(person))
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(Self.color(person)))
            .overlay(Self.ring)
            .opacity(response == .declined ? 0.4 : 1)
            .help(person.displayName)
    }

    /// Separates overlapping circles.
    static var ring: some View {
        Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
    }

    /// First letters of the first two words of the name, or of the email.
    static func initials(_ person: Person) -> String {
        let words = person.displayName.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Stable across launches, unlike `hashValue`.
    static func color(_ person: Person) -> Color {
        var hash = 0
        for unit in person.email.lowercased().unicodeScalars {
            hash = (hash &* 31 &+ Int(unit.value)) % 360
        }
        return Color(hue: Double(hash) / 360, saturation: 0.45, brightness: 0.72)
    }
}
