import Foundation
import Observation

enum PresenceKeys {
    static let supabaseURL = "presenceSupabaseURL"
    static let supabaseAnonKey = "presenceSupabaseAnonKey"
    static let nickname = "presenceNickname"
    static let deviceID = "presenceDeviceID"
    static let publishTaskName = "presencePublishTaskName"
}

enum PresenceDefaults {
    static let supabaseURL = "https://lvjjmfdgpknkiioesnzi.supabase.co"
    static let supabasePublishableKey = "sb_publishable_zb9gMwpJ5Im7U9NjdLpzWw_gwgL4zwN"
}

struct PresencePeer: Identifiable, Codable, Equatable {
    let deviceID: String
    let nickname: String
    let status: String
    let taskTitle: String?
    let categoryColor: String?
    let startedAt: Date?
    let plannedMinutes: Int
    let elapsedSeconds: Int
    let lastSeenAt: Date

    var id: String { deviceID }
    var isPaused: Bool { status == "paused" }
    var isRunning: Bool { status == "running" }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case nickname
        case status
        case taskTitle = "task_title"
        case categoryColor = "category_color"
        case startedAt = "started_at"
        case plannedMinutes = "planned_minutes"
        case elapsedSeconds = "elapsed_seconds"
        case lastSeenAt = "last_seen_at"
    }
}

struct PublicSessionSummary: Codable {
    let deviceID: String
    let nickname: String
    let startedAt: Date
    let endedAt: Date
    let elapsedSeconds: Int
    let taskTitle: String?
    let categoryColor: String?
    let ratingRaw: Int

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case nickname
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case elapsedSeconds = "elapsed_seconds"
        case taskTitle = "task_title"
        case categoryColor = "category_color"
        case ratingRaw = "rating_raw"
    }
}

struct WeeklyLeader: Identifiable, Equatable {
    let deviceID: String
    let nickname: String
    let totalSeconds: Int
    let sessionCount: Int
    let streakDays: Int        // current consecutive-day streak
    let bestStreakDays: Int    // longest run this month
    let badges: [String]
    let isCurrentUser: Bool
    // Positive = climbed vs last week, negative = dropped, 0 = same, nil = new this week.
    var rankDelta: Int? = nil

    var id: String { deviceID }
}

@MainActor
@Observable
final class PresenceService {
    static let shared = PresenceService()

    private(set) var peers: [PresencePeer] = []
    private(set) var weeklyLeaders: [WeeklyLeader] = []
    private(set) var lastError: String?
    private(set) var hasLoadedPeers = false
    private(set) var hasLoadedLeaders = false

    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?

    var deviceID: String {
        if let saved = defaults.string(forKey: PresenceKeys.deviceID), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: PresenceKeys.deviceID)
        return generated
    }

    var nickname: String {
        let saved = defaults.string(forKey: PresenceKeys.nickname)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !saved.isEmpty { return saved }
        let generated = Self.randomNickname()
        defaults.set(generated, forKey: PresenceKeys.nickname)
        return generated
    }

    var isConfigured: Bool {
        endpoint != nil && !supabaseKey.isEmpty
    }

    func startPolling() {
        ensureDefaults()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchPeers()
                await self?.fetchLeaderboard()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func refresh() {
        Task { [weak self] in
            await self?.fetchPeers()
            await self?.fetchLeaderboard()
        }
    }

    func publish(engine: FocusTimerEngine, categoryColor: String?) {
        guard isConfigured, engine.phase != .idle else { return }
        let publishTaskName = defaults.bool(forKey: PresenceKeys.publishTaskName)
        let taskTitle = publishTaskName ? engine.taskName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let peer = PresencePeer(
            deviceID: deviceID,
            nickname: nickname,
            status: engine.phase == .paused ? "paused" : "running",
            taskTitle: taskTitle.isEmpty ? nil : taskTitle,
            categoryColor: categoryColor,
            startedAt: engine.startedAt,
            plannedMinutes: engine.plannedMinutes,
            elapsedSeconds: Int(engine.elapsed.rounded()),
            lastSeenAt: .now
        )
        Task { await upsert(peer) }
    }

    func clearCurrent() {
        guard isConfigured else { return }
        Task { await deleteCurrent() }
    }

    func publishCompletedSession(result: SessionResult, elapsedSeconds: Int, endedAt: Date, rating: FocusRating, categoryColor: String?) {
        guard isConfigured, elapsedSeconds > 0 else { return }
        let publishTaskName = defaults.bool(forKey: PresenceKeys.publishTaskName)
        let taskTitle = publishTaskName ? result.taskName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let summary = PublicSessionSummary(
            deviceID: deviceID,
            nickname: nickname,
            startedAt: result.startedAt,
            endedAt: endedAt,
            elapsedSeconds: elapsedSeconds,
            taskTitle: taskTitle.isEmpty ? nil : taskTitle,
            categoryColor: categoryColor,
            ratingRaw: rating.rawValue
        )
        Task {
            await insert(summary)
            await fetchLeaderboard()
        }
    }

    private func ensureDefaults() {
        _ = deviceID
        _ = nickname
    }

    private var endpoint: URL? {
        let saved = defaults.string(forKey: PresenceKeys.supabaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = (saved.isEmpty ? PresenceDefaults.supabaseURL : saved)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private var headers: [String: String]? {
        let key = supabaseKey
        guard !key.isEmpty else { return nil }
        return [
            "apikey": key,
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ]
    }

    private var supabaseKey: String {
        let saved = defaults.string(forKey: PresenceKeys.supabaseAnonKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? PresenceDefaults.supabasePublishableKey : saved
    }

    private func fetchPeers() async {
        defer { hasLoadedPeers = true }
        guard let endpoint, let headers else {
            peers = []
            lastError = nil
            return
        }
        let cutoff = PresenceDateCoding.string(from: Date.now.addingTimeInterval(-90))
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/active_sessions"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "last_seen_at", value: "gte.\(cutoff)"),
            URLQueryItem(name: "order", value: "last_seen_at.desc")
        ]
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            let decoded = try JSONDecoder.presence.decode([PresencePeer].self, from: data)
            peers = decoded.filter { $0.deviceID != deviceID && ($0.isRunning || $0.isPaused) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchLeaderboard() async {
        defer { hasLoadedLeaders = true }
        guard let endpoint, let headers else {
            weeklyLeaders = []
            lastError = nil
            return
        }
        let calendar = Calendar.current
        let since = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -30, to: .now) ?? .now)
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/public_session_summaries"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "started_at", value: "gte.\(PresenceDateCoding.string(from: since))"),
            URLQueryItem(name: "order", value: "started_at.desc")
        ]
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            let summaries = try JSONDecoder.presence.decode([PublicSessionSummary].self, from: data)
            weeklyLeaders = makeWeeklyLeaders(from: summaries, calendar: calendar)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func upsert(_ peer: PresencePeer) async {
        guard let endpoint, let headers else { return }
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/active_sessions"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "device_id")]
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONEncoder.presence.encode(peer)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func insert(_ summary: PublicSessionSummary) async {
        guard let endpoint, let headers else { return }
        let url = endpoint.appending(path: "rest/v1/public_session_summaries")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.httpBody = try JSONEncoder.presence.encode(summary)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func deleteCurrent() async {
        guard let endpoint, let headers else { return }
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/active_sessions"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "device_id", value: "eq.\(deviceID)")]
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Supabase request failed."
            throw PresenceError.requestFailed(message)
        }
    }

    private func makeWeeklyLeaders(from summaries: [PublicSessionSummary], calendar: Calendar) -> [WeeklyLeader] {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        let prevStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let weekly = summaries.filter { $0.startedAt >= weekStart }
        let lastWeekRows = summaries.filter { $0.startedAt >= prevStart && $0.startedAt < weekStart }
        let lastWeekRank = rankMap(from: lastWeekRows)
        let grouped = Dictionary(grouping: weekly, by: \.deviceID)
        let allByDevice = Dictionary(grouping: summaries, by: \.deviceID)

        var leaders = grouped.compactMap { id, rows -> WeeklyLeader? in
            let total = rows.reduce(0) { $0 + $1.elapsedSeconds }
            guard total > 0 else { return nil }
            let latest = rows.max { $0.startedAt < $1.startedAt }
            let history = allByDevice[id] ?? rows
            let streak = streakDays(for: history, calendar: calendar)
            let best = longestStreak(for: history, calendar: calendar)
            let badges = badges(totalSeconds: total, sessionCount: rows.count, streakDays: streak)
            return WeeklyLeader(
                deviceID: id,
                nickname: latest?.nickname ?? "Anonymous",
                totalSeconds: total,
                sessionCount: rows.count,
                streakDays: streak,
                bestStreakDays: best,
                badges: badges,
                isCurrentUser: id == deviceID
            )
        }
        .sorted {
            if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds > $1.totalSeconds }
            if $0.streakDays != $1.streakDays { return $0.streakDays > $1.streakDays }
            return $0.sessionCount > $1.sessionCount
        }

        for i in leaders.indices {
            if let previous = lastWeekRank[leaders[i].deviceID] {
                leaders[i].rankDelta = previous - (i + 1)
            }
        }
        return leaders
    }

    /// Maps each device to its 1-based rank by focus time over the given rows.
    private func rankMap(from rows: [PublicSessionSummary]) -> [String: Int] {
        let totals = Dictionary(grouping: rows, by: \.deviceID)
            .mapValues { $0.reduce(0) { $0 + $1.elapsedSeconds } }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        var map: [String: Int] = [:]
        for (index, entry) in totals.enumerated() { map[entry.key] = index + 1 }
        return map
    }

    private func streakDays(for summaries: [PublicSessionSummary], calendar: Calendar) -> Int {
        let days = Set(summaries.map { calendar.startOfDay(for: $0.startedAt) })
        guard var cursor = days.max() else { return 0 }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    /// Longest run of consecutive focus days anywhere in the history window.
    private func longestStreak(for summaries: [PublicSessionSummary], calendar: Calendar) -> Int {
        let days = Set(summaries.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for i in 1..<days.count {
            if calendar.date(byAdding: .day, value: 1, to: days[i - 1]) == days[i] {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
        }
        return best
    }

    private func badges(totalSeconds: Int, sessionCount: Int, streakDays: Int) -> [String] {
        var result: [String] = []
        if totalSeconds >= 10 * 3600 { result.append("10h club") }
        else if totalSeconds >= 5 * 3600 { result.append("5h club") }
        else if totalSeconds >= 3 * 3600 { result.append("3h club") }
        if streakDays >= 7 { result.append("7-day streak") }
        else if streakDays >= 3 { result.append("3-day streak") }
        if sessionCount >= 10 { result.append("10 sessions") }
        if result.isEmpty { result.append("Started") }
        return Array(result.prefix(3))
    }

    private static func randomNickname() -> String {
        let adjectives = ["Calm", "Bright", "Steady", "Quiet", "Sharp", "Kind", "Brave", "Clear"]
        let nouns = ["Focus", "Flow", "Maker", "Thinker", "Builder", "Writer", "Learner", "Worker"]
        return "\(adjectives.randomElement() ?? "Calm") \(nouns.randomElement() ?? "Focus")"
    }
}

private enum PresenceError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return message
        }
    }
}

private enum PresenceDateCoding {
    nonisolated static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    nonisolated static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }

    private nonisolated static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private extension JSONDecoder {
    static let presence: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = PresenceDateCoding.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO8601 date."))
        }
        return decoder
    }()
}

private extension JSONEncoder {
    static let presence: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(PresenceDateCoding.string(from: date))
        }
        return encoder
    }()
}
