import SwiftUI
import CalbarCore

/// "Going?" with Yes, Maybe and No pills. The current answer is filled in
/// its color; the pills dim while an answer is being sent. An account
/// without the write scope gets a "Reconnect to reply" link instead.
struct RSVPControl: View {
    let current: ResponseStatus
    let isPending: Bool
    let isReadOnly: Bool
    let error: String?
    let onAnswer: (ResponseStatus) -> Void
    let onReconnect: () -> Void

    static let answers: [ResponseStatus] = [.accepted, .tentative, .declined]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "envelope.open")
                    .frame(width: 14)
                Text("Going?")
                    .padding(.trailing, 2)
                if isReadOnly {
                    // A plain button styled as a link: it lines up with the
                    // "Going?" label like the pills would.
                    Button(action: onReconnect) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2.weight(.semibold))
                            Text("Reconnect to reply")
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(height: 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Sign in again so Calbar may reply to invitations")
                } else {
                    HStack(spacing: 4) {
                        ForEach(Self.answers, id: \.self) { answer in
                            RSVPPill(answer: answer, isCurrent: current == answer) {
                                if answer != current { onAnswer(answer) }
                            }
                        }
                    }
                    .opacity(isPending ? 0.5 : 1)
                    .disabled(isPending)
                    .animation(.easeInOut(duration: 0.15), value: isPending)
                }
            }
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: error)
    }
}

extension ResponseStatus {
    /// Label of the answer in the RSVP control and the context menu.
    var answerLabel: String {
        switch self {
        case .accepted: "Yes"
        case .tentative: "Maybe"
        case .declined: "No"
        case .needsAction: "No answer"
        }
    }

    var answerColor: Color {
        switch self {
        case .accepted: .green
        case .tentative: .orange
        case .declined: .red
        case .needsAction: .secondary
        }
    }
}

private struct RSVPPill: View {
    let answer: ResponseStatus
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(answer.answerLabel)
                .font(.caption.weight(isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(minWidth: 34)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background {
                    if isCurrent {
                        Capsule().fill(answer.answerColor)
                    } else {
                        Capsule().fill(Color.primary.opacity(hovering ? 0.08 : 0))
                        Capsule().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Going: \(answer.answerLabel)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
