import SwiftUI
import SwiftData

/// The "Year" tab: the contribution calendar plus all-time-ish year totals.
/// Independent of the selected period range.
struct YearStatsView: View {
    @State private var year = Calendar.current.component(.year, from: Date())
    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Text(verbatim: "\(year)")
                            .font(.headline).monospacedDigit()
                        Button { year += 1 } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .disabled(year >= thisYear)
                            .opacity(year >= thisYear ? 0.3 : 1)
                        Spacer()
                    }
                    YearHeatmap(width: max(0, geo.size.width - 48), year: year)
                        .id(year)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .removeScrollers()
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// GitHub-style contribution calendar: one square per day for the last year,
/// greener the more you focused that day, with year totals above it.
struct YearHeatmap: View {
    @Query private var sessions: [FocusSession]
    let width: CGFloat
    let year: Int
    @State private var hovered: DayHover?

    private struct DayHover: Equatable { let date: Date; let seconds: Int; let future: Bool }

    private let legendCell: CGFloat = 11
    private let spacing: CGFloat = 3
    private let cal = Calendar.current

    init(width: CGFloat, year: Int) {
        self.width = width
        self.year = year
        let cal = Calendar.current
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        // A week of buffer so the aligned grid's leading partial week is covered.
        let start = cal.date(byAdding: .day, value: -7, to: jan1) ?? jan1
        let nextYear = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? jan1
        let abandoned = SessionOutcome.abandonedIdle.rawValue
        _sessions = Query(
            filter: #Predicate<FocusSession> { s in
                s.endedAt != nil && s.startedAt >= start && s.startedAt < nextYear && s.outcomeRaw != abandoned
            },
            sort: \.startedAt
        )
    }

    var body: some View {
        let m = build()
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focus calendar").font(.headline)
                Spacer()
                Text(hoverSummary(m))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.1), value: hovered)
            }

            HStack(spacing: 10) {
                statTile("Total focus", formatDurationShort(seconds: m.totalSeconds))
                statTile("Longest streak", m.longestStreak > 0 ? "\(m.longestStreak)d" : "–")
                statTile("Best month", m.bestMonthLabel)
            }

            VStack(alignment: .leading, spacing: 8) {
                let cell = cellSize(m)
                monthLabels(m, cell: cell)
                grid(m, cell: cell)
                legend
            }
        }
    }

    /// Cell edge sized so all weeks fit the given width exactly (no scroll).
    private func cellSize(_ m: Model) -> CGFloat {
        guard width > 0 else { return legendCell }
        let gaps = CGFloat(m.weeks - 1) * spacing
        return max(5, min(18, (width - gaps) / CGFloat(m.weeks)))
    }

    // MARK: - Model

    private struct Model {
        let gridStart: Date
        let yearStart: Date
        let yearEnd: Date
        let today: Date
        let weeks: Int
        let perDay: [Date: Int]
        let daysFocused: Int
        let totalSeconds: Int
        let longestStreak: Int
        let bestMonthLabel: String
    }

    private func build() -> Model {
        let today = cal.startOfDay(for: Date())
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today
        let dec31 = cal.date(from: DateComponents(year: year, month: 12, day: 31)) ?? today
        let gridStart = cal.dateInterval(of: .weekOfYear, for: jan1)?.start ?? jan1
        let totalDays = (cal.dateComponents([.day], from: gridStart, to: dec31).day ?? 0) + 1
        let weeks = Int(ceil(Double(totalDays) / 7.0))

        var perDay: [Date: Int] = [:]
        for s in sessions {
            perDay[cal.startOfDay(for: s.startedAt), default: 0] += s.elapsedSeconds
        }
        let inWindow = perDay.filter { $0.key >= jan1 && $0.key <= today && $0.value > 0 }

        let totalSeconds = inWindow.values.reduce(0, +)
        let daysFocused = inWindow.count

        // Longest consecutive-day run this year.
        var longest = 0, run = 0
        var prev: Date?
        for day in inWindow.keys.sorted() {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = day
        }

        // Best month by focus time.
        var monthTotals: [DateComponents: Int] = [:]
        for (day, secs) in inWindow {
            monthTotals[cal.dateComponents([.year, .month], from: day), default: 0] += secs
        }
        let bestMonthLabel = monthTotals.max { $0.value < $1.value }
            .flatMap { cal.date(from: $0.key) }?
            .formatted(.dateTime.month(.abbreviated)) ?? "–"

        return Model(gridStart: gridStart, yearStart: jan1, yearEnd: dec31, today: today, weeks: weeks,
                     perDay: perDay, daysFocused: daysFocused, totalSeconds: totalSeconds,
                     longestStreak: longest, bestMonthLabel: bestMonthLabel)
    }

    // MARK: - Pieces

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 10))
    }

    private func grid(_ m: Model, cell: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<m.weeks, id: \.self) { w in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { r in
                        cellView(week: w, row: r, model: m, cell: cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(week: Int, row: Int, model m: Model, cell: CGFloat) -> some View {
        let d = date(week: week, row: row, m)
        if d < m.yearStart || d > m.yearEnd {
            Color.clear.frame(width: cell, height: cell)          // outside this year
        } else if d > m.today {
            RoundedRectangle(cornerRadius: 2)                     // future day → outline
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .frame(width: cell, height: cell)
                .help(tooltip(d, 0))
                .onHover { hover(d, seconds: 0, future: true, $0) }
        } else {
            let seconds = m.perDay[d] ?? 0
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: seconds))
                .frame(width: cell, height: cell)
                .help(tooltip(d, seconds))
                .onHover { hover(d, seconds: seconds, future: false, $0) }
        }
    }

    private func date(week: Int, row: Int, _ m: Model) -> Date {
        cal.date(byAdding: .day, value: week * 7 + row, to: m.gridStart) ?? m.gridStart
    }

    private func hover(_ d: Date, seconds: Int, future: Bool, _ hovering: Bool) {
        if hovering {
            hovered = DayHover(date: d, seconds: seconds, future: future)
        } else if hovered?.date == d {
            hovered = nil
        }
    }

    /// Header-right text: the hovered day's detail, or the year's day count.
    private func hoverSummary(_ m: Model) -> String {
        if let h = hovered {
            let day = h.date.formatted(.dateTime.month().day())
            if h.future { return "\(day) · upcoming" }
            return h.seconds > 0 ? "\(day) · \(formatDurationShort(seconds: h.seconds))" : "\(day) · no focus"
        }
        return "\(m.daysFocused) day\(m.daysFocused == 1 ? "" : "s") focused"
    }

    private func monthLabels(_ m: Model, cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarks(m), id: \.week) { mark in
                Text(mark.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(mark.week) * (cell + spacing))
            }
        }
        .frame(width: CGFloat(m.weeks) * (cell + spacing), height: 11, alignment: .topLeading)
    }

    private func monthMarks(_ m: Model) -> [(week: Int, label: String)] {
        var marks: [(week: Int, label: String)] = []
        var last = -1
        for w in 0..<m.weeks {
            let d = max(date(week: w, row: 0, m), m.yearStart)
            let month = cal.component(.month, from: d)
            if month != last {
                marks.append((w, d.formatted(.dateTime.month(.abbreviated))))
                last = month
            }
        }
        return marks
    }

    private func color(for seconds: Int) -> Color {
        if seconds <= 0 { return Color.primary.opacity(0.06) }
        switch seconds / 60 {
        case ..<30: return Color.green.opacity(0.30)
        case ..<60: return Color.green.opacity(0.52)
        case ..<120: return Color.green.opacity(0.74)
        default: return Color.green
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach([0, 20, 45, 90, 150], id: \.self) { minutes in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: minutes * 60))
                    .frame(width: legendCell, height: legendCell)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func tooltip(_ date: Date, _ seconds: Int) -> String {
        let d = date.formatted(.dateTime.month().day().year())
        return seconds > 0 ? "\(d) · \(formatDurationShort(seconds: seconds))" : "\(d) · no focus"
    }
}
