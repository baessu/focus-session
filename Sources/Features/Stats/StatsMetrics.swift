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
    let bestFocusHour: FocusHourInsight?
    let focusHours: [FocusHourInsight]
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

        var hourAcc: [Int: Double] = [:]
        var hourQualityAcc: [Int: (weightedRating: Int, seconds: Int, sessions: Int, focused: Int)] = [:]
        for s in sessions {
            // Peak hour: spread the focused time across every clock hour the
            // session actually spans, so a long session isn't dumped entirely
            // into its start hour.
            for (hour, seconds) in Self.hourlyDistribution(of: s, calendar: cal) {
                hourAcc[hour, default: 0] += seconds
            }

            // Quality buckets (best focus hour) stay keyed by start hour.
            let startHour = cal.component(.hour, from: s.startedAt)
            let rating = min(2, max(0, s.ratingRaw))
            hourQualityAcc[startHour, default: (0, 0, 0, 0)].weightedRating += rating * s.elapsedSeconds
            hourQualityAcc[startHour, default: (0, 0, 0, 0)].seconds += s.elapsedSeconds
            hourQualityAcc[startHour, default: (0, 0, 0, 0)].sessions += 1
            if rating == FocusRating.focused.rawValue {
                hourQualityAcc[startHour, default: (0, 0, 0, 0)].focused += 1
            }
        }
        peakHour = hourAcc.max { $0.value < $1.value }?.key
        focusHours = hourQualityAcc.map { hour, bucket in
            let score = bucket.seconds > 0
                ? Double(bucket.weightedRating) / Double(bucket.seconds * FocusRating.focused.rawValue) * 100
                : 0
            return FocusHourInsight(
                hour: hour,
                score: score,
                seconds: bucket.seconds,
                sessionCount: bucket.sessions,
                focusedCount: bucket.focused
            )
        }
        .sorted { $0.hour < $1.hour }
        bestFocusHour = focusHours.max {
            if abs($0.score - $1.score) >= 0.5 { return $0.score < $1.score }
            if $0.seconds != $1.seconds { return $0.seconds < $1.seconds }
            return $0.sessionCount < $1.sessionCount
        }

        var ratings: [Int: Int] = [:]
        for s in sessions { ratings[s.ratingRaw, default: 0] += 1 }
        ratingCounts = ratings

        var prevCat: [String: Int] = [:]
        for s in previous { prevCat[s.activity?.category?.name ?? StatsAggregator.uncategorizedName, default: 0] += s.elapsedSeconds }
        prevCategorySeconds = prevCat
    }

    /// Splits a session's focused seconds across every clock hour it spans,
    /// weighted by the wall-clock overlap with each hour. Pauses (which sit in
    /// the start→end span but not in `elapsedSeconds`) are spread evenly by
    /// scaling the overlap so the parts sum back to `elapsedSeconds`.
    private static func hourlyDistribution(of s: FocusSession, calendar cal: Calendar) -> [Int: Double] {
        let elapsed = Double(s.elapsedSeconds)
        guard let end = s.endedAt else {
            return [cal.component(.hour, from: s.startedAt): elapsed]
        }
        let span = end.timeIntervalSince(s.startedAt)
        guard span > 0 else {
            return [cal.component(.hour, from: s.startedAt): elapsed]
        }

        var result: [Int: Double] = [:]
        var cursor = s.startedAt
        while cursor < end {
            let hour = cal.component(.hour, from: cursor)
            let nextBoundary = cal.nextDate(after: cursor,
                                            matching: DateComponents(minute: 0, second: 0),
                                            matchingPolicy: .nextTime) ?? end
            let segmentEnd = min(nextBoundary, end)
            let overlap = segmentEnd.timeIntervalSince(cursor)
            result[hour, default: 0] += overlap / span * elapsed
            cursor = segmentEnd
        }
        return result
    }

    func hourLabel(_ h: Int) -> String {
        let ampm = h < 12 ? "AM" : "PM"
        let hr = h % 12 == 0 ? 12 : h % 12
        return "\(hr) \(ampm)"
    }
}

struct FocusHourInsight: Identifiable {
    var id: Int { hour }
    let hour: Int
    let score: Double
    let seconds: Int
    let sessionCount: Int
    let focusedCount: Int

    var roundedScore: Int { Int(score.rounded()) }
}

/// Formats a signed fraction as "+12%" / "−58%" (nil → empty).
func formatDelta(_ delta: Double?) -> (text: String, up: Bool)? {
    guard let delta, abs(delta) >= 0.005 else { return nil }
    let pct = Int((delta * 100).rounded())
    return (String(format: "%+d%%", pct), delta > 0)
}
