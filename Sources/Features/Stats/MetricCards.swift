import SwiftUI

struct MetricCards: View {
    let metrics: StatsMetrics

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "Total focus", value: formatDurationShort(seconds: metrics.totalSeconds), delta: metrics.totalDelta)
            MetricCard(title: "Avg / day", value: formatDurationShort(seconds: metrics.avgPerDaySeconds), delta: metrics.avgDelta)
            MetricCard(title: "Peak hour", value: metrics.peakHour.map { metrics.hourLabel($0) } ?? "–", delta: nil)
            MetricCard(title: "Sessions", value: "\(metrics.sessionCount)", delta: nil)
            MetricCard(title: "Avg session", value: formatDurationShort(seconds: metrics.avgSessionSeconds), delta: nil)
            MetricCard(title: "Longest", value: formatDurationShort(seconds: metrics.longestSeconds), delta: nil)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let delta: Double?

    var body: some View {
        VStack(spacing: 3) {
            if let d = formatDelta(delta) {
                HStack(spacing: 2) {
                    Text(d.text)
                    Image(systemName: d.up ? "arrow.up" : "arrow.down")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(d.up ? Color.green : Color.red)
            } else {
                Text(" ").font(.caption2)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
    }
}

struct RatingRow: View {
    let metrics: StatsMetrics

    var body: some View {
        HStack(spacing: 0) {
            ForEach([FocusRating.focused, .neutral, .distracted]) { rating in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: rating.arrow).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text("\(metrics.ratingCounts[rating.rawValue] ?? 0)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(rating.emoji)
                    }
                    Text(rating.label).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
    }
}
