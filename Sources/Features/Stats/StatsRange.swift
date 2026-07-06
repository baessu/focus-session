import Foundation

/// The active analytics window. Either a navigable unit period (day / week /
/// month containing an anchor) or a fixed rolling window (last N days).
struct StatsRange: Equatable {
    enum Mode: Equatable {
        case day, week, month
        case rolling(Int)
    }

    var mode: Mode
    var anchor: Date

    private static var cal: Calendar { .current }

    // MARK: Presets

    static func today(_ now: Date = .now) -> StatsRange { .init(mode: .day, anchor: now) }
    static func yesterday(_ now: Date = .now) -> StatsRange {
        .init(mode: .day, anchor: cal.date(byAdding: .day, value: -1, to: now) ?? now)
    }
    static func thisWeek(_ now: Date = .now) -> StatsRange { .init(mode: .week, anchor: now) }
    static func lastWeek(_ now: Date = .now) -> StatsRange {
        .init(mode: .week, anchor: cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now)
    }
    static func thisMonth(_ now: Date = .now) -> StatsRange { .init(mode: .month, anchor: now) }
    static func lastMonth(_ now: Date = .now) -> StatsRange {
        .init(mode: .month, anchor: cal.date(byAdding: .month, value: -1, to: now) ?? now)
    }
    static func rolling(_ days: Int, _ now: Date = .now) -> StatsRange { .init(mode: .rolling(days), anchor: now) }

    // MARK: Bounds (half-open [lower, upper))

    func bounds() -> (lower: Date, upper: Date) {
        let cal = Self.cal
        switch mode {
        case .day:
            let start = cal.startOfDay(for: anchor)
            return (start, cal.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let interval = cal.dateInterval(of: .weekOfYear, for: anchor)
            return (interval?.start ?? anchor, interval?.end ?? anchor)
        case .month:
            let interval = cal.dateInterval(of: .month, for: anchor)
            return (interval?.start ?? anchor, interval?.end ?? anchor)
        case .rolling(let n):
            let startOfToday = cal.startOfDay(for: anchor)
            let upper = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            let lower = cal.date(byAdding: .day, value: -(n - 1), to: startOfToday) ?? startOfToday
            return (lower, upper)
        }
    }

    /// The previous, equal-length window (for period-over-period comparison).
    func previous() -> StatsRange {
        switch mode {
        case .rolling(let n):
            return .init(mode: .rolling(n), anchor: Self.cal.date(byAdding: .day, value: -n, to: anchor) ?? anchor)
        default:
            return shifted(by: -1)
        }
    }

    var isNavigable: Bool { if case .rolling = mode { return false } else { return true } }

    func shifted(by step: Int) -> StatsRange {
        let component: Calendar.Component
        switch mode {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .rolling: return self
        }
        return .init(mode: mode, anchor: Self.cal.date(byAdding: component, value: step, to: anchor) ?? anchor)
    }

    /// The unit used when bucketing the daily-distribution chart.
    var bucketsAreHours: Bool { mode == .day }

    // MARK: Labels

    func title(_ now: Date = .now) -> String {
        let cal = Self.cal
        switch mode {
        case .day:
            if cal.isDate(anchor, inSameDayAs: now) { return "Today" }
            if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(anchor, inSameDayAs: y) { return "Yesterday" }
            return anchor.formatted(.dateTime.month().day())
        case .week:
            if cal.isDate(anchor, equalTo: now, toGranularity: .weekOfYear) { return "This Week" }
            if let lw = cal.date(byAdding: .weekOfYear, value: -1, to: now),
               cal.isDate(anchor, equalTo: lw, toGranularity: .weekOfYear) { return "Last Week" }
            let b = bounds()
            return "\(b.lower.formatted(.dateTime.month().day())) – \(cal.date(byAdding: .day, value: -1, to: b.upper)?.formatted(.dateTime.month().day()) ?? "")"
        case .month:
            if cal.isDate(anchor, equalTo: now, toGranularity: .month) { return "This Month" }
            if let lm = cal.date(byAdding: .month, value: -1, to: now),
               cal.isDate(anchor, equalTo: lm, toGranularity: .month) { return "Last Month" }
            return anchor.formatted(.dateTime.year().month(.wide))
        case .rolling(let n):
            return "Last \(n) Days"
        }
    }

    /// Explicit "from – to" span of the current window (inclusive end).
    func rangeSpanLabel() -> String {
        let cal = Self.cal
        let b = bounds()
        let end = cal.date(byAdding: .day, value: -1, to: b.upper) ?? b.upper
        let start = b.lower.formatted(.dateTime.month().day())
        let endStr = end.formatted(.dateTime.month().day())
        return start == endStr ? start : "\(start) – \(endStr)"
    }

    /// Short two-line label for the surrounding-period chip strip.
    func chipLines() -> (top: String, bottom: String) {
        let cal = Self.cal
        switch mode {
        case .day:
            return (cal.shortWeekdaySymbols[(cal.component(.weekday, from: anchor) - 1) % 7],
                    "\(cal.component(.day, from: anchor))")
        case .week:
            let b = bounds()
            let end = cal.date(byAdding: .day, value: -1, to: b.upper) ?? b.upper
            return (b.lower.formatted(.dateTime.month().day()) + " →", end.formatted(.dateTime.month().day()))
        case .month:
            return (anchor.formatted(.dateTime.year()), anchor.formatted(.dateTime.month(.wide)))
        case .rolling(let n):
            return ("Last", "\(n)d")
        }
    }

    /// Surrounding periods for the chip strip (2 before … 2 after).
    func chips() -> [StatsRange] { (-2...2).map { shifted(by: $0) } }
}
