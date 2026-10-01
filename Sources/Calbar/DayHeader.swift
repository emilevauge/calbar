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

/// Month calendar in a popover under the day title: month arrows, a menu
/// on the year, the days of the month, and "Today". The graphical
/// DatePicker has no way to change the year but month by month.
struct DayPicker: View {
    let day: Date
    let isToday: Bool
    let onPick: (Date) -> Void
    let onToday: () -> Void
    /// First day of the month shown.
    @State private var month: Date

    private static let calendar = Calendar.current
    private static let english = Locale(identifier: "en_US")

    init(day: Date, isToday: Bool, onPick: @escaping (Date) -> Void, onToday: @escaping () -> Void) {
        self.day = day
        self.isToday = isToday
        self.onPick = onPick
        self.onToday = onToday
        _month = State(initialValue: Self.firstOfMonth(day))
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdays
            grid
            Button("Today", action: onToday)
                .controlSize(.small)
        }
        .padding(10)
        .frame(width: 232)
        // The first control takes the keyboard focus on opening; its blue
        // focus ring looks like a stray border.
        .focusEffectDisabled()
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 2) {
            IconButton("chevron.left", tooltip: "Previous month") { shift(months: -1) }
            Spacer(minLength: 0)
            Text(month.formatted(.dateTime.month(.wide).locale(Self.english)))
                .font(.headline)
            yearMenu
            Spacer(minLength: 0)
            IconButton("chevron.right", tooltip: "Next month") { shift(months: 1) }
        }
    }

    private var yearMenu: some View {
        let year = Self.calendar.component(.year, from: month)
        let now = Self.calendar.component(.year, from: Date())
        return Menu {
            ForEach((now - 10)...(now + 5), id: \.self) { y in
                Button(String(y)) { shift(months: (y - year) * 12) }
            }
        } label: {
            Text(String(year))
                .font(.headline)
                .monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Pick a year")
    }

    // MARK: days

    /// Very short names in English, from the user's first weekday.
    private var weekdays: some View {
        var english = Calendar(identifier: .gregorian)
        english.locale = Self.english
        let symbols = english.veryShortStandaloneWeekdaySymbols
        let first = Self.calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let cal = Self.calendar
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead)
            + (0..<count).map { cal.date(byAdding: .day, value: $0, to: month) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 26)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = Self.calendar
        let selected = cal.isDate(date, inSameDayAs: day)
        let today = cal.isDateInToday(date)
        return Button {
            onPick(date)
        } label: {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 12, weight: today || selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? AnyShapeStyle(.white) : today ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .frame(width: 26, height: 26)
                .background {
                    if selected {
                        Circle().fill(Color.accentColor)
                    } else if today {
                        Circle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: navigation

    private func shift(months: Int) {
        if let next = Self.calendar.date(byAdding: .month, value: months, to: month) {
            month = next
        }
    }

    private static func firstOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
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
