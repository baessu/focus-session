import Foundation
import Observation
import SwiftData

enum PresenceKeys {
    static let supabaseURL = "presenceSupabaseURL"
    static let supabaseAnonKey = "presenceSupabaseAnonKey"
    static let nickname = "presenceNickname"
    static let emoji = "presenceEmoji"
    static let deviceID = "presenceDeviceID"
    static let publishTaskName = "presencePublishTaskName"
}

enum PresenceDefaults {
    static let supabaseURL = "https://lvjjmfdgpknkiioesnzi.supabase.co"
    static let supabasePublishableKey = "sb_publishable_zb9gMwpJ5Im7U9NjdLpzWw_gwgL4zwN"
}

enum PresenceDefaultsMigration {
    /// 1.2 dropped the app sandbox, which moves UserDefaults from the sandbox
    /// container to the standard location. Carry over the community identity
    /// (device id, name, emoji, settings) once so upgrading users keep their
    /// profile and published history instead of getting a fresh device id.
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        let flag = "presenceDefaultsMigratedFromSandbox"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)

        let containerPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.baessu.focussession/Data/Library/Preferences/com.baessu.focussession.plist")
        guard let saved = NSDictionary(contentsOf: containerPlist) as? [String: Any] else { return }

        // The container holds the user's real prior identity — prefer it, even if
        // an interim non-sandbox launch already generated a fresh device id.
        let keys = [
            PresenceKeys.deviceID, PresenceKeys.nickname, PresenceKeys.emoji,
            PresenceKeys.publishTaskName, PresenceKeys.supabaseURL, PresenceKeys.supabaseAnonKey,
        ]
        for key in keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
        }
    }
}

struct PresencePeer: Identifiable, Codable, Equatable {
    let deviceID: String
    let nickname: String
    let emoji: String?
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
        case emoji
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
    var clientID: UUID?
    let deviceID: String
    let nickname: String
    let startedAt: Date
    let endedAt: Date
    let elapsedSeconds: Int
    let taskTitle: String?
    let categoryColor: String?
    let ratingRaw: Int

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
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

    var profileEmoji: String {
        (defaults.string(forKey: PresenceKeys.emoji) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            emoji: profileEmoji.isEmpty ? nil : profileEmoji,
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

    /// Publish (or update) a completed session's summary, keyed by a stable
    /// client id so editing the same session updates its row instead of adding one.
    func publishFocusSession(clientID: UUID, startedAt: Date, endedAt: Date, elapsedSeconds: Int,
                             taskTitle: String?, categoryColor: String?, rating: FocusRating) {
        guard isConfigured, elapsedSeconds > 0 else { return }
        let shareTask = defaults.bool(forKey: PresenceKeys.publishTaskName)
        let trimmed = shareTask ? (taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : ""
        let summary = PublicSessionSummary(
            clientID: clientID,
            deviceID: deviceID,
            nickname: nickname,
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedSeconds: elapsedSeconds,
            taskTitle: trimmed.isEmpty ? nil : trimmed,
            categoryColor: categoryColor,
            ratingRaw: rating.rawValue
        )
        Task {
            await upsert(summary)
            await fetchLeaderboard()
        }
    }

    /// Remove a session's summary from the community (deleted or converted away).
    func unpublishFocusSession(clientID: UUID) {
        guard isConfigured else { return }
        Task {
            await deleteSummary(clientID: clientID)
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

    /// One-time recovery after local data loss: rebuild `FocusSession` rows from
    /// this device's community summaries. Task names were never uploaded, so
    /// recovered sessions carry only time, rating, and the category color —
    /// grouped under a "(recovered)" activity per category. Summaries already
    /// present locally (matched by `publicID`) are skipped, so it is safe to run
    /// more than once.
    func recoverSessionsFromServer(context: ModelContext) async -> (inserted: Int, total: Int) {
        guard let endpoint, let headers else { return (0, 0) }
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/public_session_summaries"),
                                             resolvingAgainstBaseURL: false) else { return (0, 0) }
        components.queryItems = [
            URLQueryItem(name: "device_id", value: "eq.\(deviceID)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "started_at.asc"),
        ]
        guard let url = components.url else { return (0, 0) }

        let summaries: [PublicSessionSummary]
        do {
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            summaries = try JSONDecoder.presence.decode([PublicSessionSummary].self, from: data)
        } catch {
            lastError = error.localizedDescription
            return (0, 0)
        }

        let existing = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        let existingPublicIDs = Set(existing.compactMap(\.publicID))
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        var recoveredActivities: [String: Activity] = [:]   // colorHex -> "(recovered)" activity
        var inserted = 0

        for summary in summaries {
            guard let clientID = summary.clientID, !existingPublicIDs.contains(clientID) else { continue }

            let colorHex = summary.categoryColor ?? "#8E8E93"
            let activity = recoveredActivities[colorHex] ?? {
                let category = categories.first { $0.colorHex == colorHex }
                let a = Activity(name: "(recovered)", category: category)
                a.syncID = UUID()
                context.insert(a)
                recoveredActivities[colorHex] = a
                return a
            }()

            let planned = max(1, Int((Double(summary.elapsedSeconds) / 60).rounded()))
            let session = FocusSession(
                startedAt: summary.startedAt,
                endedAt: summary.endedAt,
                plannedMinutes: planned,
                elapsedSeconds: summary.elapsedSeconds,
                outcome: .completed,
                activity: activity
            )
            session.ratingRaw = summary.ratingRaw
            session.publicID = clientID
            session.syncID = UUID()
            session.updatedAt = .now
            context.insert(session)
            inserted += 1
        }

        try? context.save()
        return (inserted, summaries.count)
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

    private func upsert(_ summary: PublicSessionSummary) async {
        guard let endpoint, let headers else { return }
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/public_session_summaries"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "client_id")]
        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONEncoder.presence.encode(summary)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func deleteSummary(clientID: UUID) async {
        guard let endpoint, let headers else { return }
        guard var components = URLComponents(url: endpoint.appending(path: "rest/v1/public_session_summaries"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "client_id", value: "eq.\(clientID.uuidString)")]
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

// MARK: - Community publishing helpers (any completed FocusSession)

/// Publish or update a session's community summary, assigning a stable public id
/// on first publish. Works for timer-completed and timetable-created/edited sessions.
@MainActor
func publishSessionToCommunity(_ session: FocusSession, context: ModelContext) {
    guard session.endedAt != nil, session.elapsedSeconds > 0 else { return }
    if session.publicID == nil {
        session.publicID = UUID()
        try? context.save()
    }
    guard let id = session.publicID, let endedAt = session.endedAt else { return }
    PresenceService.shared.publishFocusSession(
        clientID: id,
        startedAt: session.startedAt,
        endedAt: endedAt,
        elapsedSeconds: session.elapsedSeconds,
        taskTitle: session.activity?.name,
        categoryColor: session.activity?.category?.colorHex,
        rating: session.rating
    )
}

/// Remove a session's summary from the community (on delete / convert to schedule).
@MainActor
func unpublishSessionFromCommunity(_ session: FocusSession) {
    if let id = session.publicID {
        PresenceService.shared.unpublishFocusSession(clientID: id)
    }
}

/// One-time backfill: publish all recent completed sessions to the community
/// (upsert is idempotent, so re-running is safe). Returns how many were queued.
@MainActor
@discardableResult
func backfillCommunity(context: ModelContext, days: Int = 35) -> Int {
    let cal = Calendar.current
    let cutoff = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) ?? Date()
    let abandoned = SessionOutcome.abandonedIdle.rawValue
    let descriptor = FetchDescriptor<FocusSession>(
        predicate: #Predicate { s in
            s.endedAt != nil && s.elapsedSeconds > 0 && s.startedAt >= cutoff && s.outcomeRaw != abandoned
        }
    )
    guard let sessions = try? context.fetch(descriptor) else { return 0 }
    for session in sessions {
        publishSessionToCommunity(session, context: context)
    }
    return sessions.count
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
        fractional.string(from: date)
    }

    /// Postgres omits the fractional part for whole-second timestamps, so accept
    /// both `...:00.000Z` and `...:00Z`.
    nonisolated static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }

    private nonisolated static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private nonisolated static var plain: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
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
