import Foundation

// MARK: - Date range presets

enum RangePreset: String, CaseIterable, Identifiable {
    case today, last7, last30

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .last7: return "7 Days"
        case .last30: return "30 Days"
        }
    }

    /// Half-open [lower, upper) day bounds for the preset.
    func bounds(now: Date, calendar: Calendar) -> (lower: Date, upper: Date) {
        let startOfToday = calendar.startOfDay(for: now)
        let upper = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        switch self {
        case .today:
            return (startOfToday, upper)
        case .last7:
            return (calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday, upper)
        case .last30:
            return (calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday, upper)
        }
    }
}

// MARK: - Aggregated value types (Charts-friendly)

struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let seconds: Int
}

struct TaskTotal: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let seconds: Int
}

struct DailyCategoryBucket: Identifiable {
    let id: String
    let day: Date
    let categoryName: String
    let colorHex: String
    let seconds: Int
}

// MARK: - Aggregator

/// Reduces a fetched set of FocusSession rows into the three chart datasets.
/// Grouping is done in Swift; the SwiftData predicate only filters stored scalars.
struct StatsAggregator {
    let totalSeconds: Int
    let categories: [CategoryTotal]      // sorted desc by seconds
    let tasks: [TaskTotal]               // sorted desc by seconds
    let daily: [DailyCategoryBucket]     // for the stacked bar
    let isEmpty: Bool

    static let uncategorizedName = "Uncategorized"
    static let uncategorizedHex = "#8E8E93"

    init(sessions: [FocusSession], calendar: Calendar) {
        var total = 0
        var catAcc: [String: (name: String, hex: String, secs: Int)] = [:]
        var taskAcc: [String: (name: String, hex: String, secs: Int)] = [:]
        var dayAcc: [String: (day: Date, name: String, hex: String, secs: Int)] = [:]

        for session in sessions {
            let secs = session.elapsedSeconds
            guard secs > 0 else { continue }
            total += secs

            let category = session.activity?.category
            let catName = category?.name ?? Self.uncategorizedName
            let hex = category?.colorHex ?? Self.uncategorizedHex
            let taskName = session.activity?.name ?? "Untitled"
            let day = calendar.startOfDay(for: session.startedAt)

            catAcc[catName, default: (catName, hex, 0)].secs += secs

            let taskKey = "\(catName)|\(taskName)"
            taskAcc[taskKey, default: (taskName, hex, 0)].secs += secs

            let dayKey = "\(day.timeIntervalSince1970)|\(catName)"
            dayAcc[dayKey, default: (day, catName, hex, 0)].secs += secs
        }

        totalSeconds = total
        categories = catAcc
            .map { CategoryTotal(id: $0.key, name: $0.value.name, colorHex: $0.value.hex, seconds: $0.value.secs) }
            .sorted { $0.seconds > $1.seconds }
        tasks = taskAcc
            .map { TaskTotal(id: $0.key, name: $0.value.name, colorHex: $0.value.hex, seconds: $0.value.secs) }
            .sorted { $0.seconds > $1.seconds }
        daily = dayAcc
            .map { DailyCategoryBucket(id: $0.key, day: $0.value.day, categoryName: $0.value.name, colorHex: $0.value.hex, seconds: $0.value.secs) }
            .sorted { $0.day < $1.day }
        isEmpty = total == 0
    }

    /// Stable name -> color map so the donut, stacked bar, and legend agree.
    var colorDomainRange: (domain: [String], range: [String]) {
        var seen = Set<String>()
        var domain: [String] = []
        var range: [String] = []
        for c in categories where !seen.contains(c.name) {
            seen.insert(c.name)
            domain.append(c.name)
            range.append(c.colorHex)
        }
        return (domain, range)
    }
}
