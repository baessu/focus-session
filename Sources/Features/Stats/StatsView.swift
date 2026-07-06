import SwiftUI
import SwiftData
import Charts

enum StatsTab: Hashable { case period, year }

struct StatsView: View {
    @State private var range: StatsRange = .rolling(7)
    @State private var notesOnly = false
    @State private var tab: StatsTab = .period

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Period").tag(StatsTab.period)
                Text("Year").tag(StatsTab.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            switch tab {
            case .period: periodContent
            case .year: YearStatsView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var periodContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                StatsRangeBar(range: $range)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            RangedStatsContent(range: range, notesOnly: $notesOnly)
        }
    }
}

/// Owns the date-bounded @Query so SwiftData re-runs the fetch when the range changes.
private struct RangedStatsContent: View {
    @Query private var sessions: [FocusSession]
    @Query private var prevSessions: [FocusSession]
    @Binding var notesOnly: Bool

    private let timelineWidth: CGFloat = 360
    private let twoColumnBreakpoint: CGFloat = 880

    init(range: StatsRange, notesOnly: Binding<Bool>) {
        _notesOnly = notesOnly
        let b = range.bounds()
        let p = range.previous().bounds()
        let abandoned = SessionOutcome.abandonedIdle.rawValue
        let lo = b.lower, hi = b.upper, plo = p.lower, phi = p.upper
        _sessions = Query(
            filter: #Predicate<FocusSession> { s in
                s.endedAt != nil && s.startedAt >= lo && s.startedAt < hi && s.outcomeRaw != abandoned
            },
            sort: \.startedAt
        )
        _prevSessions = Query(
            filter: #Predicate<FocusSession> { s in
                s.endedAt != nil && s.startedAt >= plo && s.startedAt < phi && s.outcomeRaw != abandoned
            },
            sort: \.startedAt
        )
    }

    var body: some View {
        let agg = StatsAggregator(sessions: sessions, calendar: .current)
        let metrics = StatsMetrics(sessions: sessions, previous: prevSessions)

        if agg.isEmpty {
            ContentUnavailableView(
                "No focus in this range",
                systemImage: "moon.zzz",
                description: Text("Sessions you finish in this range will show up here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                if geo.size.width >= twoColumnBreakpoint {
                    HStack(spacing: 0) {
                        dashboardScroll(agg, metrics)
                            .frame(maxWidth: .infinity)
                        Divider()
                        timelineColumn
                            .frame(width: timelineWidth)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            dashboard(agg, metrics)
                            timelineHeader
                            SessionTimeline(sessions: sessions, notesOnly: notesOnly)
                        }
                        .padding(24)
                        .removeScrollers()
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func dashboardScroll(_ agg: StatsAggregator, _ metrics: StatsMetrics) -> some View {
        ScrollView {
            dashboard(agg, metrics)
                .padding(24)
                .removeScrollers()
        }
        .scrollIndicators(.hidden)
    }

    private func dashboard(_ agg: StatsAggregator, _ metrics: StatsMetrics) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            MetricCards(metrics: metrics)
            RatingRow(metrics: metrics)
            BestFocusTimeChart(metrics: metrics)
            CategoryDonut(agg: agg, metrics: metrics)
            DailyStackedChart(agg: agg, avgPerDaySeconds: metrics.avgPerDaySeconds)
            TaskRankBar(agg: agg)
        }
    }

    private var timelineColumn: some View {
        VStack(spacing: 0) {
            timelineHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            ScrollView {
                SessionTimeline(sessions: sessions, notesOnly: notesOnly)
                    .padding(16)
                    .removeScrollers()
            }
            .scrollIndicators(.hidden)
        }
    }

    private var timelineHeader: some View {
        HStack(spacing: 12) {
            Text("Sessions").font(.headline)
            Spacer()
            Toggle("Notes only", isOn: $notesOnly)
                .toggleStyle(.checkbox)
                .font(.caption)
            Button { SessionExporter.exportCSV(sessions) } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Export sessions as CSV")
        }
    }
}

// MARK: - Best focus time

private struct BestFocusTimeChart: View {
    let metrics: StatsMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Best focus time")
                Spacer()
                if let best = metrics.bestFocusHour {
                    Text("\(metrics.hourLabel(best.hour)) · \(best.roundedScore)% focus")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if metrics.focusHours.count == 1, let only = metrics.focusHours.first {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metrics.hourLabel(only.hour))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("\(only.sessionCount) session\(only.sessionCount == 1 ? "" : "s") · \(formatDurationShort(seconds: only.seconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(only.roundedScore)%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(14)
                .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
            } else {
                Chart(metrics.focusHours) { bucket in
                    BarMark(
                        x: .value("Hour", bucket.hour),
                        y: .value("Focus score", bucket.score)
                    )
                    .foregroundStyle(bucket.hour == metrics.bestFocusHour?.hour ? Color.accentColor : Color.primary.opacity(0.28))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        if bucket.hour == metrics.bestFocusHour?.hour {
                            Text("\(bucket.roundedScore)%")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("focus")
                .chartXAxis {
                    AxisMarks(values: Array(stride(from: 0, through: 21, by: 3))) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(metrics.hourLabel(hour))
                            }
                        }
                    }
                }
                .frame(height: 160)

                HStack(spacing: 10) {
                    Image(systemName: "sparkline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Score weights your focus rating by focused time in each start hour.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Category donut

private struct CategoryDonut: View {
    var agg: StatsAggregator
    var metrics: StatsMetrics

    var body: some View {
        let scale = agg.colorDomainRange
        let total = max(1, agg.totalSeconds)
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("By category")
            HStack(alignment: .center, spacing: 20) {
                Chart(agg.categories) { item in
                    SectorMark(
                        angle: .value("Seconds", item.seconds),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("Category", item.name))
                }
                .chartForegroundStyleScale(domain: scale.domain, range: scale.range.map { Color(hex: $0) })
                .chartLegend(.hidden)
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(agg.categories) { item in
                        let pct = Int((Double(item.seconds) / Double(total) * 100).rounded())
                        let prev = metrics.prevCategorySeconds[item.name] ?? 0
                        let delta = prev > 0 ? Double(item.seconds - prev) / Double(prev) : nil
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: item.colorHex)).frame(width: 9, height: 9)
                            Text(item.name).font(.callout)
                            Spacer(minLength: 10)
                            Text("\(pct)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                            if let d = formatDelta(delta) {
                                HStack(spacing: 1) {
                                    Text(d.text); Image(systemName: d.up ? "arrow.up" : "arrow.down")
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(d.up ? .green : .red)
                                .frame(width: 52, alignment: .trailing)
                            } else {
                                Text("–").font(.caption2).foregroundStyle(.tertiary).frame(width: 52, alignment: .trailing)
                            }
                            Text(formatDurationShort(seconds: item.seconds))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Daily stacked bar

private struct DailyStackedChart: View {
    var agg: StatsAggregator
    var avgPerDaySeconds: Int

    var body: some View {
        let scale = agg.colorDomainRange
        let avgMinutes = Double(avgPerDaySeconds) / 60.0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("By day")
                Spacer()
                if avgPerDaySeconds > 0 {
                    Text("avg \(formatDurationShort(seconds: avgPerDaySeconds))/day")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(agg.daily) { bucket in
                    BarMark(
                        x: .value("Day", bucket.day, unit: .day),
                        y: .value("Minutes", Double(bucket.seconds) / 60.0)
                    )
                    .foregroundStyle(by: .value("Category", bucket.categoryName))
                    .cornerRadius(3)
                }
                if avgMinutes > 0 {
                    RuleMark(y: .value("Average", avgMinutes))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale(domain: scale.domain, range: scale.range.map { Color(hex: $0) })
            .chartLegend(.hidden)
            .chartYAxisLabel("min")
            .frame(height: 200)
        }
    }
}

// MARK: - Ranked task bar

private struct TaskRankBar: View {
    var agg: StatsAggregator
    private var top: [TaskTotal] { Array(agg.tasks.prefix(8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Top tasks")
            Chart(top) { task in
                BarMark(
                    x: .value("Minutes", Double(task.seconds) / 60.0),
                    y: .value("Task", task.name)
                )
                .foregroundStyle(Color(hex: task.colorHex))
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(formatDurationShort(seconds: task.seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxisLabel("min")
            .frame(height: CGFloat(max(1, top.count)) * 34 + 30)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.headline)
    }
}
