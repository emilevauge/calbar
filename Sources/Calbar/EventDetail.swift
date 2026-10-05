import SwiftUI
import AppKit
import CalbarCore

/// Expanded part of a row or card: answer, link, place, guests,
/// documents, description. The actions sit in the row's or card's top
/// line (`EventActions`).
struct EventDetail: View {
    let event: CalendarEvent
    /// Off when the row or card already has a Join button.
    var showsMeetingLink = true
    @State private var showAllAttendees = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            lines
            if let notes = event.notes {
                let text = HTMLText.plainText(notes)
                if !text.isEmpty {
                    Text(Linkify.attributed(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.caption)
        // Plain text is secondary; clickable items opt back into the accent.
        .foregroundStyle(.secondary)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 8) {
            if event.canRespond {
                RSVPSection(event: event)
            }
            if showsMeetingLink, let meeting = event.meeting {
                line("video") {
                    Button(meeting.provider.displayName) { MeetingOpener.open(meeting) }
                        .buttonStyle(.link)
                        .clickable()
                }
            }
            if let location = event.location, !location.isEmpty {
                line("mappin.and.ellipse") {
                    Button(location) { openLocation(location) }
                        .buttonStyle(.link)
                        .clickable()
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            if let organizer = event.organizer, !event.attendees.contains(where: \.isOrganizer) {
                line("person.crop.circle") { Text("Organized by \(organizer.displayName)") }
            }
            if !event.attendees.isEmpty {
                attendees
            }
            if !event.attachments.isEmpty {
                attachments
            }
        }
    }

    private func line<Content: View>(_ symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .frame(width: 14)
            content()
        }
    }

    // MARK: attendees

    private var sortedAttendees: [Attendee] {
        event.attendees.sorted { (rank($0), $0.person.displayName) < (rank($1), $1.person.displayName) }
    }

    private func rank(_ a: Attendee) -> Int {
        if a.isOrganizer { return 0 }
        switch a.response {
        case .accepted: return 1
        case .tentative: return 2
        case .needsAction: return 3
        case .declined: return 4
        }
    }

    /// Initials and a count; a click lists every guest with their answer.
    private var attendees: some View {
        let all = sortedAttendees
        let yes = all.filter { $0.response == .accepted }.count

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(Motion.resize) { showAllAttendees.toggle() }
            } label: {
                HStack(spacing: 8) {
                    AvatarStack(attendees: all)
                    Text(all.count == 1 ? "1 guest" : "\(all.count) guests · \(yes) yes")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAllAttendees ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showAllAttendees ? "Hide guests" : "Show guests")

            if showAllAttendees {
                ForEach(all, id: \.person.email) { attendee in
                    HStack(spacing: 6) {
                        responseIcon(attendee.response)
                            .frame(width: 14)
                        Text(attendee.person.displayName)
                            .lineLimit(1)
                            .help(attendee.person.email)
                        if attendee.isOrganizer {
                            Text("organizer").foregroundStyle(.tertiary)
                        } else if attendee.isOptional {
                            Text("optional").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 3)
                }
            }
        }
    }

    @ViewBuilder
    private func responseIcon(_ response: ResponseStatus) -> some View {
        switch response {
        case .accepted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .declined:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .tentative:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        case .needsAction:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        }
    }

    // MARK: attachments

    /// Documents as chips that open them.
    private var attachments: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(event.attachments, id: \.url) { file in
                Link(destination: file.url) {
                    HStack(spacing: 4) {
                        Image(systemName: file.symbolName)
                        Text(file.title)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickable()
                .help(file.title)
            }
        }
    }

    // MARK: actions

    private func openLocation(_ location: String) {
        if let url = URL(string: location), url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
            return
        }
        var c = URLComponents(string: "maps://")!
        c.queryItems = [URLQueryItem(name: "q", value: location)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}

/// Edit, duplicate, delete and open in Google Calendar, at the top right
/// of a card or expanded row. Edit and delete on the user's own events
/// only. A deletion goes at once, with 10 seconds to undo from the bar
/// above the footer; for a recurring event the trash asks which
/// occurrences first.
struct EventActions: View {
    let event: CalendarEvent
    /// The Join button of a row, last, in the same style.
    var onJoin: (() -> Void)?
    @ObservedObject private var store = AppDelegate.shared.store

    var body: some View {
        HStack(spacing: 2) {
            if store.canEdit(event) {
                ActionIcon(help: "Edit this event", action: { store.edit(event) }) {
                    Image(systemName: "square.and.pencil")
                }
            }
            if event.attendees.contains(where: { !$0.isSelf }) {
                ActionIcon(help: store.canEdit(event) ? "Find a time: guests' availability, to move it"
                                                      : "Guests' availability",
                           action: { withAnimation(Motion.resize) { store.startFindingTime(for: event) } }) {
                    Image(systemName: "calendar.badge.clock")
                }
            }
            if !AppDelegate.shared.accounts.writableCalendars.isEmpty {
                ActionIcon(help: "Duplicate this event", action: { store.duplicate(event) }) {
                    Image(systemName: "plus.square.on.square")
                }
            }
            if store.canDelete(event) {
                if event.isRecurring {
                    ActionIcon(help: "Delete this recurring event (⌫)", hoverColor: .red, menu: {
                        ForEach(RecurrenceScope.allCases, id: \.self) { scope in
                            Button(scope.label) { withAnimation(Motion.resize) { store.delete(event, scope: scope) } }
                        }
                    }) {
                        Image(systemName: "trash")
                    }
                } else {
                    ActionIcon(help: "Delete this event (⌫)", hoverColor: .red, action: {
                        withAnimation(Motion.resize) { store.delete(event) }
                    }) {
                        Image(systemName: "trash")
                    }
                }
            }
            if let url = event.webURL {
                ActionIcon(help: "Open in Google Calendar", action: { NSWorkspace.shared.open(url) }) {
                    GoogleCalendarIcon(size: 13.5)
                }
            }
            if let onJoin, let meeting = event.meeting {
                ActionIcon(help: "Join on \(meeting.provider.displayName)", tint: .accentColor, action: onJoin) {
                    Image(systemName: "video")
                }
            }
        }
    }
}

/// One small icon of `EventActions`: 26 by 24, secondary (or `tint`),
/// on a light rounded square on hover; a button, or a menu with `menu`.
struct ActionIcon<Glyph: View, Items: View>: View {
    let help: String
    var hoverColor: Color = .primary
    var tint: Color?
    let action: (() -> Void)?
    let menu: (() -> Items)?
    @ViewBuilder let glyph: () -> Glyph
    @State private var hovering = false

    init(help: String, hoverColor: Color = .primary, tint: Color? = nil, action: @escaping () -> Void,
         @ViewBuilder glyph: @escaping () -> Glyph) where Items == EmptyView {
        self.help = help
        self.hoverColor = hoverColor
        self.tint = tint
        self.action = action
        self.menu = nil
        self.glyph = glyph
    }

    init(help: String, hoverColor: Color = .primary, tint: Color? = nil,
         @ViewBuilder menu: @escaping () -> Items, @ViewBuilder glyph: @escaping () -> Glyph) {
        self.help = help
        self.hoverColor = hoverColor
        self.tint = tint
        self.action = nil
        self.menu = menu
        self.glyph = glyph
    }

    private var face: some View {
        glyph()
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(hovering ? AnyShapeStyle(hoverColor) : tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .frame(width: 26, height: 24)
            .background(Color.primary.opacity(hovering ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if let menu {
                // A plain button style keeps the face as drawn, the same
                // square as the buttons.
                Menu(content: menu) { face }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
            } else if let action {
                Button(action: action) { face }
                    .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The RSVP control bound to the store: answers, pending state, errors,
/// and the account's permission to reply.
private struct RSVPSection: View {
    let event: CalendarEvent
    @ObservedObject private var store = AppDelegate.shared.store
    @ObservedObject private var accounts = AppDelegate.shared.accounts

    var body: some View {
        RSVPControl(
            current: event.selfResponse,
            isPending: store.pendingAnswers.contains(event.id),
            isReadOnly: !accounts.canReply(event.accountEmail),
            error: store.answerErrors[event.id],
            onAnswer: { store.respond(to: event, with: $0) },
            onReconnect: { AppDelegate.shared.addAccount(loginHint: event.accountEmail) }
        )
    }
}

private extension View {
    /// Accent color for links and link-style buttons, which would otherwise
    /// inherit the container's secondary style and look like plain text.
    func clickable() -> some View {
        foregroundStyle(Color.accentColor)
    }
}

extension Attachment {
    /// SF Symbol matching the file type, for attachment rows.
    var symbolName: String {
        switch mimeType ?? "" {
        case let m where m.contains("document"): return "doc.text"
        case let m where m.contains("spreadsheet"): return "tablecells"
        case let m where m.contains("presentation"): return "rectangle.on.rectangle"
        case let m where m.contains("pdf"): return "doc.richtext"
        default: return "paperclip"
        }
    }
}
