import Foundation

/// Summary metrics for the current window, with period-over-period deltas.
struct StatsMetrics {
    let totalSeconds: Int
    let totalDelta: Double?          // fraction vs previous period (nil if no baseline)
    let avgPerDaySeconds: Int
    let avgDelta: Double?
    let sessionCount: Int
    let avgSessionSeconds: Int
    let longestSeconds: Int
    let peakHour: Int?               // hour-of-day with the most focus
    let ratingCounts: [Int: Int]     // ratingRaw -> count
    let prevCategorySeconds: [String: Int]

    init(sessions: [FocusSession], previous: [FocusSession]) {
        let cal = Calendar.current
        let total = sessions.reduce(0) { $0 + $1.elapsedSeconds }
        let prevTotal = previous.reduce(0) { $0 + $1.elapsedSeconds }

        totalSeconds = total
        totalDelta = prevTotal > 0 ? Double(total - prevTotal) / Double(prevTotal) : nil

        let activeDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) }).count
        avgPerDaySeconds = activeDays > 0 ? total / activeDays : 0
        let prevActiveDays = Set(previous.map { cal.startOfDay(for: $0.startedAt) }).count
        let prevAvg = prevActiveDays > 0 ? prevTotal / prevActiveDays : 0
        avgDelta = prevAvg > 0 ? Double(avgPerDaySeconds - prevAvg) / Double(prevAvg) : nil

        sessionCount = sessions.count
        avgSessionSeconds = sessions.isEmpty ? 0 : total / sessions.count
        longestSeconds = sessions.map(\.elapsedSeconds).max() ?? 0

        var hourAcc: [Int: Int] = [:]
        for s in sessions { hourAcc[cal.component(.hour, from: s.startedAt), default: 0] += s.elapsedSeconds }
        peakHour = hourAcc.max { $0.value < $1.value }?.key

        var ratings: [Int: Int] = [:]
        for s in sessions { ratings[s.ratingRaw, default: 0] += 1 }
        ratingCounts = ratings

        var prevCat: [String: Int] = [:]
        for s in previous { prevCat[s.activity?.category?.name ?? StatsAggregator.uncategorizedName, default: 0] += s.elapsedSeconds }
        prevCategorySeconds = prevCat
    }

    func hourLabel(_ h: Int) -> String {
        let ampm = h < 12 ? "AM" : "PM"
        let hr = h % 12 == 0 ? 12 : h % 12
        return "\(hr) \(ampm)"
    }
}

/// Formats a signed fraction as "+12%" / "−58%" (nil → empty).
func formatDelta(_ delta: Double?) -> (text: String, up: Bool)? {
    guard let delta, abs(delta) >= 0.005 else { return nil }
    let pct = Int((delta * 100).rounded())
    return (String(format: "%+d%%", pct), delta > 0)
}
