import SwiftUI
import CalbarCore

/// The day's availability in the event editor: an "Everyone" line with
/// the times free for all in green, then one line per person, busy times
/// hatched, over the hours of the week grid; the event's time framed
/// across them. A click moves the event there; "Next free" jumps to the
/// next time free for everyone, on this day or the next ones.
struct AvailabilityStrip: View {
    struct Row: Identifiable {
        let email: String
        let name: String
        var id: String { email }
    }

    let rows: [Row]
    /// Busy times by lowercased email, the edited event's own time out.
    let busy: [String: [DateInterval]]
    /// Lowercased emails Google does not share.
    let unknown: Set<String>
    /// Where the event fits for everyone, on the days read.
    let free: [DateInterval]
    let start: Date
    let end: Date
    let startHour: Int
    let endHour: Int
    let isLoading: Bool
    let error: String?
    let onPick: (Date) -> Void

    private static let labelWidth: CGFloat = 58
    private static let rowHeight: CGFloat = 13

    private var calendar: Calendar { .current }
    private var midnight: Date { calendar.startOfDay(for: start) }
    /// The grid's hours, widened to the event's.
    private var hours: ClosedRange<Int> {
        let first = min(startHour, calendar.component(.hour, from: start))
        let endsAt = calendar.dateComponents([.hour, .minute], from: midnight, to: end)
        let last = max(endHour, min((endsAt.hour ?? 0) + ((endsAt.minute ?? 0) > 0 ? 1 : 0), 24))
        return first...max(last, first + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(DayHeaderText.shortTitle(start))
                    .foregroundStyle(.secondary)
                if isLoading { ProgressView().controlSize(.mini) }
                if let error {
                    Text(error).foregroundStyle(.red).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    if let next = nextFree() { onPick(next) }
                } label: {
                    HStack(spacing: 3) {
                        Text("Next free")
                        Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(nextFree() == nil)
                .help("Move to the next time free for everyone")
            }
            .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 3) {
                line(label: "Everyone", bold: true) { width in
                    ForEach(Array(spans(free).enumerated()), id: \.offset) { _, span in
                        Rectangle().fill(Color.green.opacity(0.55))
                            .frame(width: span.width * width).offset(x: span.x * width)
                    }
                    ForEach(Array(spans(FreeBusy.union(busy.values.flatMap { $0 })).enumerated()), id: \.offset) { _, span in
                        busyBand.frame(width: span.width * width).offset(x: span.x * width)
                    }
                }
                ForEach(rows) { row in
                    line(label: row.name, bold: false, unknown: unknown.contains(row.email)) { width in
                        ForEach(Array(spans(busy[row.email] ?? []).enumerated()), id: \.offset) { _, span in
                            busyBand.frame(width: span.width * width).offset(x: span.x * width)
                        }
                    }
                    .help(unknown.contains(row.email) ? "\(row.email): calendar not shared" : row.email)
                }
            }
            .overlay(alignment: .topLeading) { slotFrame }
            .overlay(alignment: .topLeading) { clickArea }

            hourLabels
        }
    }

    // MARK: parts

    private var busyBand: some View {
        Rectangle().fill(Color.primary.opacity(0.28))
    }

    /// A person or "Everyone", then their line over the hours.
    private func line<Bands: View>(label: String, bold: Bool, unknown: Bool = false,
                                   @ViewBuilder bands: @escaping (CGFloat) -> Bands) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5, weight: bold ? .semibold : .regular))
                .foregroundStyle(unknown ? .tertiary : .secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.06))
                    if unknown {
                        Text("not shared").font(.system(size: 8.5)).foregroundStyle(.tertiary).padding(.leading, 4)
                    } else {
                        bands(geo.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .frame(height: Self.rowHeight)
        }
    }

    /// The event's time, across every line.
    private var slotFrame: some View {
        GeometryReader { geo in
            let width = geo.size.width - Self.labelWidth - 6
            let span = fraction(DateInterval(start: start, end: max(end, start)))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                .frame(width: max(span.width * width, 3), height: geo.size.height + 4)
                .offset(x: Self.labelWidth + 6 + span.x * width, y: -2)
        }
        .allowsHitTesting(false)
    }

    /// A click on the lines: the event starts there, to the quarter hour.
    private var clickArea: some View {
        GeometryReader { geo in
            let width = geo.size.width - Self.labelWidth - 6
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width)
                .offset(x: Self.labelWidth + 6)
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    let x = min(max(value.location.x / max(width, 1), 0), 1)
                    let minute = Double(hours.lowerBound * 60) + x * Double((hours.upperBound - hours.lowerBound) * 60)
                    let quarter = Int(minute) - Int(minute) % 15
                    onPick(midnight.addingTimeInterval(TimeInterval(quarter * 60)))
                })
        }
    }

    private var hourLabels: some View {
        GeometryReader { geo in
            let width = geo.size.width - Self.labelWidth - 6
            let count = hours.upperBound - hours.lowerBound
            let step = count > 8 ? 3 : count > 4 ? 2 : 1
            ForEach(Array(stride(from: hours.lowerBound, through: hours.upperBound, by: step)), id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: Self.labelWidth + 6 + CGFloat(hour - hours.lowerBound) / CGFloat(count) * width - 5)
            }
        }
        .frame(height: 11)
    }

    // MARK: geometry

    /// Position and width of `span` on the line, as fractions.
    private func fraction(_ span: DateInterval) -> (x: CGFloat, width: CGFloat) {
        let open = midnight.addingTimeInterval(TimeInterval(hours.lowerBound * 3600))
        let total = TimeInterval((hours.upperBound - hours.lowerBound) * 3600)
        let a = min(max(span.start.timeIntervalSince(open) / total, 0), 1)
        let b = min(max(span.end.timeIntervalSince(open) / total, 0), 1)
        return (CGFloat(a), CGFloat(b - a))
    }

    private func spans(_ list: [DateInterval]) -> [(x: CGFloat, width: CGFloat)] {
        list.map(fraction).filter { $0.width > 0 }
    }

    /// The next quarter hour after the current start where the event fits
    /// for everyone.
    private func nextFree() -> Date? {
        let duration = end.timeIntervalSince(start)
        var after = start.addingTimeInterval(60)
        for _ in 0..<200 {
            guard let found = FreeBusy.nextFree(after: after, duration: duration, free: free) else { return nil }
            let minutes = Int(found.timeIntervalSince(calendar.startOfDay(for: found)) / 60)
            let rounded = calendar.startOfDay(for: found)
                .addingTimeInterval(TimeInterval(((minutes + 14) / 15) * 15 * 60))
            if free.contains(where: { $0.start <= rounded && rounded.addingTimeInterval(duration) <= $0.end }) {
                return rounded
            }
            after = rounded
        }
        return nil
    }
}
