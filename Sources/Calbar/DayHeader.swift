import SwiftUI
import CalbarCore

/// Top bar of the popover: the day title with a caption below it, and the
/// previous and next day buttons grouped on the right.
struct DayHeader<Info: View>: View {
    let day: Date
    let isToday: Bool
    let onChange: (Int) -> Void
    let onToday: () -> Void
    /// A day picked in the calendar opened by a click on the title.
    let onPick: (Date) -> Void
    @ViewBuilder let info: () -> Info
    @State private var picking = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                title
                info()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                IconButton("chevron.left", tooltip: "Previous day") { onChange(-1) }
                IconButton("chevron.right", tooltip: "Next day") { onChange(1) }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
    }

    /// A click on the title opens a month calendar to pick any day.
    private var title: some View {
        Button {
            picking.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(DayHeaderText.title(day))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pick a day")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            DayPicker(day: day, isToday: isToday) { picked in
                picking = false
                onPick(picked)
            } onToday: {
                picking = false
                onToday()
            }
        }
    }
}

/// Month calendar in a popover under the day title.
private struct DayPicker: View {
    let day: Date
    let isToday: Bool
    let onPick: (Date) -> Void
    let onToday: () -> Void
    @State private var selection: Date

    init(day: Date, isToday: Bool, onPick: @escaping (Date) -> Void, onToday: @escaping () -> Void) {
        self.day = day
        self.isToday = isToday
        self.onPick = onPick
        self.onToday = onToday
        _selection = State(initialValue: day)
    }

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("Day", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                // It takes the keyboard focus on opening, and its blue
                // focus ring looks like a stray border.
                .focusEffectDisabled()
                .onChange(of: selection) { _, picked in
                    onPick(picked)
                }
            Button("Today", action: onToday)
                .controlSize(.small)
                .disabled(isToday)
        }
        .padding(10)
    }
}

extension DayHeader where Info == Text? {
    /// Caption for a day other than today: "Tomorrow · 3 events", or
    /// whichever part applies.
    static func otherDayInfo(_ content: DayContent, offset: Int) -> Text? {
        let count: String? = if case .loaded(let listing) = content { AgendaFormat.eventCount(listing.count) } else { nil }
        let parts = [DayWindow.relativeName(offset: offset), count].compactMap { $0 }
        return parts.isEmpty ? nil : Text(parts.joined(separator: " · "))
    }
}

enum DayHeaderText {
    /// "Tuesday, September 29", in English whatever the system locale.
    static func title(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Locale(identifier: "en_US")))
    }
}
