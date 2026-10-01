import SwiftUI
import AppKit
import CalbarCore

/// One event of the list. The meeting of the moment is a card: title,
/// progress, a prominent Join button and its details. Every other event is
/// a timeline row: start and end in a column, a bar in the calendar color
/// (dashed while the invitation waits for an answer), the title, and a
/// discreet join button; a click expands its details below.
struct EventRow: View {
    static let timeColumnWidth: CGFloat = 38

    let event: CalendarEvent
    let now: Date
    let selected: Bool
    let expanded: Bool
    let isPast: Bool
    /// Off for days other than today: the row shows the duration instead
    /// of "in 26 h", and nothing is highlighted as ongoing.
    var showsRelative = true
    /// Drawn as the card, always expanded.
    var isFocus = false
    let onToggle: () -> Void
    let onJoin: () -> Void

    private var color: Color { Color(hex: event.colorHex) }
    private var isOngoing: Bool { showsRelative && event.start <= now && now < event.end }
    /// Over and not a zero-length reminder still due: nothing to join.
    private var isOver: Bool { now >= event.end && now > event.start }
    private var canJoin: Bool { event.meeting != nil && !isPast && !isOver }
    private var awaitsAnswer: Bool { event.canRespond && event.selfResponse == .needsAction }
    private var isDeclined: Bool { event.selfResponse == .declined }

    @ObservedObject private var store = AppDelegate.shared.store

    var body: some View {
        Group {
            // Editing happens in place of the card or row; a copy is a
            // new event, in a popover beside it.
            if let request = store.editRequest, request.eventID == event.id, !request.duplicate {
                EventEditor(.edit(event), composer: AppDelegate.shared.composer, embedded: true,
                            onDone: store.endEditing)
            } else if isFocus {
                card.contextMenu { contextMenu }
            } else {
                row.contextMenu { contextMenu }
            }
        }
        .popover(isPresented: Binding(get: { store.editRequest == .init(eventID: event.id, duplicate: true) }, set: { shown in
            if !shown, store.editRequest?.eventID == event.id { store.editRequest = nil }
        }), arrowEdge: .leading) {
            EventEditor(.duplicate(event), composer: AppDelegate.shared.composer, onDone: { store.editRequest = nil })
        }
    }

    // MARK: card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isOngoing {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("NOW")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        Text("\(AgendaFormat.timeRange(event, calendar: .current)) · \(AgendaFormat.remaining(event, now: now))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        EventActions(event: event)
                            // On the caption line without making it taller.
                            .padding(.vertical, -4)
                    }
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let meeting = event.meeting, canJoin {
                    Button(action: onJoin) {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Join on \(meeting.provider.displayName)")
                }
            }
            if isOngoing {
                MeetingProgress(event: event, now: now)
            }
            EventDetail(event: event, showsMeetingLink: !canJoin)
        }
        .padding(12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape.fill(color.opacity(0.07))
            shape.strokeBorder(selected ? Color.accentColor.opacity(0.6) : color.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: row

    private var row: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(AgendaFormat.clock(event.start, .current))
                        .font(.system(size: 12, weight: .semibold))
                    Text(AgendaFormat.clock(event.end, .current))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .monospacedDigit()
                .frame(width: Self.timeColumnWidth, alignment: .trailing)

                bar

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(isDeclined)
                        .foregroundStyle(isDeclined ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(expanded ? 3 : 1)
                        .truncationMode(.tail)
                    meta
                    if isOngoing {
                        MeetingProgress(event: event, now: now)
                            .padding(.top, 3)
                    }
                }

                Spacer(minLength: 0)

                if expanded {
                    EventActions(event: event, onJoin: canJoin ? onJoin : nil)
                        .padding(.top, -2)
                } else if let meeting = event.meeting, canJoin {
                    ActionIcon(help: "Join on \(meeting.provider.displayName)", tint: .accentColor, action: onJoin) {
                        Image(systemName: "video")
                    }
                    .padding(.top, -2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if expanded {
                EventDetail(event: event, showsMeetingLink: !canJoin)
                    .padding(.leading, 14 + Self.timeColumnWidth + 10 + 3.5 + 10)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
            }
        }
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .padding(.horizontal, 6)
            }
        }
        .opacity(isPast || isDeclined ? 0.55 : 1)
    }

    /// Solid in the calendar color, dashed while the invitation waits for
    /// an answer, hollow once declined, like Google Calendar.
    @ViewBuilder
    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        Group {
            if awaitsAnswer {
                shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
            } else if isDeclined {
                shape.strokeBorder(color, lineWidth: 1.2)
            } else {
                shape.fill(color)
            }
        }
        .frame(width: 3.5)
    }

    /// Relative time or duration, then the answer state, guests,
    /// attachments and place.
    private var meta: some View {
        HStack(spacing: 8) {
            if awaitsAnswer, !isPast {
                Text("Needs reply")
                    .foregroundStyle(.orange)
                    .fixedSize()
            } else if isDeclined {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle")
                    Text("Declined")
                }
                .foregroundStyle(.red)
                .fixedSize()
            } else if showsRelative {
                // Only this text may shrink, so the icons stay visible.
                Text(AgendaFormat.relative(event, now: now))
                    .foregroundStyle(isOngoing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            } else {
                Text(AgendaFormat.duration(event.end.timeIntervalSince(event.start)))
                    .fixedSize()
            }
            if !expanded {
                badges
            }
        }
        .lineLimit(1)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Guests, attachments and place, in the collapsed row only; the
    /// expanded detail lists them in full.
    @ViewBuilder
    private var badges: some View {
        let attendees = event.attendees
        let attachments = event.attachments
        if attendees.count > 1 {
            let accepted = attendees.filter { $0.response == .accepted }.count
            badge("person.2", "\(attendees.count)")
                .fixedSize()
                .help("\(attendees.count) guests · \(accepted) yes")
        }
        if !attachments.isEmpty {
            badge("paperclip", attachments.count > 1 ? "\(attachments.count)" : nil)
                .fixedSize()
                .help(attachments.map(\.title).joined(separator: "\n"))
        }
        if let location = event.location, !location.isEmpty, !location.hasPrefix("http") {
            badge("mappin", location)
                .truncationMode(.tail)
        }
    }

    private func badge(_ symbol: String, _ text: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if let text {
                Text(text).monospacedDigit()
            }
        }
    }

    /// Right click: answer the invitation, open the event in Google Calendar.
    @ViewBuilder
    private var contextMenu: some View {
        let accounts = AppDelegate.shared.accounts
        if event.canRespond {
            let canReply = accounts.canReply(event.accountEmail)
            let pending = store.pendingAnswers.contains(event.id)
            ForEach(RSVPControl.answers, id: \.self) { answer in
                Toggle("Going: \(answer.answerLabel)", isOn: Binding(
                    get: { event.selfResponse == answer },
                    set: { _ in store.respond(to: event, with: answer) }
                ))
                .disabled(!canReply || pending)
            }
            if !canReply {
                Button("Reconnect to reply") {
                    AppDelegate.shared.addAccount(loginHint: event.accountEmail)
                }
            }
            Divider()
        }
        if let url = event.webURL {
            Button("Open in Google Calendar") { NSWorkspace.shared.open(url) }
        }
        Divider()
        if store.canEdit(event) {
            Button("Edit Event…") { store.edit(event) }
        }
        if !AppDelegate.shared.accounts.writableCalendars.isEmpty {
            Button("Duplicate Event…") { store.duplicate(event) }
        }
        if store.canDelete(event) {
            if event.isRecurring {
                Menu("Delete Event") {
                    ForEach(RecurrenceScope.allCases, id: \.self) { scope in
                        Button(scope.label) { withAnimation(Motion.resize) { store.delete(event, scope: scope) } }
                    }
                }
            } else {
                Button("Delete Event") {
                    withAnimation(Motion.resize) { store.delete(event) }
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
    }

}

/// Elapsed part of an ongoing meeting, like Claudette's context bar:
/// green, then yellow, orange and red as the end nears.
struct MeetingProgress: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        let total = event.end.timeIntervalSince(event.start)
        let fraction = total > 0 ? min(max(now.timeIntervalSince(event.start) / total, 0), 1) : 1
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.35))
                if fraction > 0 {
                    Capsule()
                        .fill(Self.color(for: fraction))
                        .frame(width: max(2, geometry.size.width * fraction))
                }
            }
        }
        .frame(height: 3.5)
        .help("\(AgendaFormat.duration(now.timeIntervalSince(event.start))) of \(AgendaFormat.duration(total)) · \(Int((fraction * 100).rounded()))%")
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent elapsed")
    }

    static func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.50: Color(red: 0.20, green: 0.78, blue: 0.35)
        case ..<0.75: Color(red: 0.95, green: 0.75, blue: 0.10)
        case ..<0.90: Color(red: 1.00, green: 0.58, blue: 0.00)
        default: Color(red: 0.92, green: 0.26, blue: 0.21)
        }
    }
}
