import SwiftUI
import MacalCore

struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let selected: Bool
    let expanded: Bool
    let isPast: Bool
    /// Off for days other than today: the row shows the time range only,
    /// without "in 26 h" or the ongoing highlight.
    var showsRelative = true
    let onToggle: () -> Void
    let onJoin: () -> Void

    private var isOngoing: Bool { showsRelative && event.start <= now && now < event.end }
    /// Over and not a zero-length reminder still due: nothing to join.
    private var isOver: Bool { now >= event.end && now > event.start }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                CalendarDot(hex: event.colorHex)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .lineLimit(expanded ? 3 : 1)
                        .truncationMode(.tail)

                    HStack(spacing: 4) {
                        Text(AgendaFormat.timeRange(event, calendar: .current))
                            .monospacedDigit()
                            .fixedSize()
                            .layoutPriority(2)
                        if showsRelative {
                            Text("·")
                                .fixedSize()
                            // Only this text may shrink, so the time range and icons stay visible.
                            Text(AgendaFormat.relative(event, now: now))
                                .foregroundStyle(isOngoing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                                .truncationMode(.tail)
                        }
                        if event.selfResponse == .declined {
                            Text("· declined")
                                .fixedSize()
                                .layoutPriority(1)
                        }
                        if !expanded {
                            metadata
                                .fixedSize()
                                .layoutPriority(1)
                        }
                    }
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let meeting = event.meeting, !isPast, !isOver {
                    Button(action: onJoin) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 20)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Join on \(meeting.provider.displayName)")
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if expanded {
                EventDetail(event: event)
                    .padding(.leading, 36)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(background)
        .opacity(isPast ? 0.55 : 1)
    }

    /// Attendee and attachment badges shown in the collapsed row; the expanded detail lists them in full.
    @ViewBuilder
    private var metadata: some View {
        let attendees = event.attendees
        let attachments = event.attachments
        if attendees.count > 1 || !attachments.isEmpty {
            HStack(spacing: 8) {
                if attendees.count > 1 {
                    let accepted = attendees.filter { $0.response == .accepted }.count
                    HStack(spacing: 3) {
                        Image(systemName: "person.2")
                        Text("\(attendees.count)")
                            .monospacedDigit()
                    }
                    .help("\(attendees.count) guests · \(accepted) yes")
                }
                if !attachments.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                        if attachments.count > 1 {
                            Text("\(attachments.count)")
                                .monospacedDigit()
                        }
                    }
                    .help(attachments.map(\.title).joined(separator: "\n"))
                }
            }
            .padding(.leading, 4)
        }
    }

    private var background: Color {
        if selected { return Color.accentColor.opacity(0.18) }
        if isOngoing { return Color.accentColor.opacity(0.07) }
        return .clear
    }
}

/// Calendar color dot with a soft halo, same shape as Claudette's status dot.
struct CalendarDot: View {
    let hex: String

    var body: some View {
        let color = Color(hex: hex)
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 16, height: 16)
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
        }
    }
}
