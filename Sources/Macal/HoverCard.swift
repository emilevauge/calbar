import SwiftUI
import MacalCore

/// Card shown while the pointer rests on the Macal item. With a due
/// meeting it matches the capsule: a header band tinted with the same
/// urgency color and its text in that color, then the meeting in a
/// material body. Otherwise the meeting the
/// glyph counts down to. Takes plain values so the controller can rebuild
/// it on every tick.
struct HoverCard: View {
    static let width: CGFloat = 300

    let events: [CalendarEvent]
    let now: Date
    let needsReconnect: Bool
    /// The meeting the capsule joins, with its color.
    var due: (event: CalendarEvent, style: CapsuleStyle)?

    var body: some View {
        let ongoing = NextMeeting.ongoing(events: events, now: now)
            .flatMap { $0.occurrenceKey == due?.event.occurrenceKey ? nil : $0 }
        VStack(alignment: .leading, spacing: 0) {
            if let due {
                DueBand(event: due.event, now: now, style: due.style)
            }
            VStack(alignment: .leading, spacing: 8) {
                if needsReconnect {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("An account needs to be reconnected")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                }
                if let ongoing {
                    OngoingLine(event: ongoing, now: now)
                }
                if needsReconnect || ongoing != nil {
                    Divider()
                }
                if let due {
                    DueSummary(event: due.event)
                } else if let next = NextMeeting.find(events: events, now: now, calendar: .current) {
                    NextMeetingSummary(event: next, now: now)
                } else {
                    Text("Nothing left today")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

/// Header of the card for a due meeting, the capsule's color and text.
/// A light tint of the color over the material rather than a white band:
/// a white strip on the dark material card glares, the tint reads as the
/// same family in both modes.
private struct DueBand: View {
    let event: CalendarEvent
    let now: Date
    let style: CapsuleStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The darker text orange is for light backgrounds; on the dark
        // card systemOrange itself is the more legible one.
        let ink = Color(nsColor: scheme == .dark ? style.color : style.textColor)
        HStack(spacing: 6) {
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(AgendaFormat.headline(event, now: now))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(AgendaFormat.timeRange(event, calendar: .current))
                .fixedSize()
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: style.color).opacity(scheme == .dark ? 0.18 : 0.12))
        .overlay(alignment: .bottom) {
            Color(nsColor: style.color).opacity(0.25).frame(height: 0.5)
        }
    }
}

/// The meeting the capsule joins. Display only: the panel ignores the
/// mouse, the footer tells where to click.
private struct DueSummary: View {
    let event: CalendarEvent
    private static let attachmentLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                CalendarDot(hex: event.colorHex)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if let meeting = event.meeting {
                            DetailLine(icon: "video", text: meeting.provider.displayName)
                        }
                        if let location = event.location, !location.isEmpty {
                            DetailLine(icon: "mappin.and.ellipse", text: location)
                        }
                        if event.attendees.count > 1 {
                            DetailLine(icon: "person.2", text: "\(event.attendees.count) guests")
                        }
                        ForEach(event.attachments.prefix(Self.attachmentLimit), id: \.url) { file in
                            DetailLine(icon: file.symbolName, text: file.title)
                        }
                        if event.attachments.count > Self.attachmentLimit {
                            DetailLine(icon: "ellipsis",
                                       text: "\(event.attachments.count - Self.attachmentLimit) more attachments")
                        }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
            }
            Text("Click: join · right-click: options")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OngoingLine: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(spacing: 0) {
            Text("Now: \(event.title)")
                .truncationMode(.tail)
            Text(" · \(AgendaFormat.duration(event.end.timeIntervalSince(now))) left")
                .monospacedDigit()
                .fixedSize()
        }
        .lineLimit(1)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct NextMeetingSummary: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CalendarDot(hex: event.colorHex)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(AgendaFormat.timeRange(event, calendar: .current)) · \(AgendaFormat.relative(event, now: now))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let meeting = event.meeting {
                    DetailLine(icon: "video", text: meeting.provider.displayName)
                }
                if let location = event.location, !location.isEmpty {
                    DetailLine(icon: "mappin.and.ellipse", text: location)
                }
                if event.attendees.count > 1 {
                    DetailLine(icon: "person.2", text: "\(event.attendees.count) guests")
                }
            }
            .font(.caption)
            Spacer(minLength: 0)
        }
    }
}

private struct DetailLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .frame(width: 14)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }
}
