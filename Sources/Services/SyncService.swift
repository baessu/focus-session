import Foundation
import SwiftData
import Observation

// MARK: - On-disk format

/// One device's full snapshot, written to `<folder>/FocusSessionSync/<deviceID>.json`.
/// Every device writes only its own file, so the user's cloud never has to
/// resolve a write conflict; merging is the union of all device files by syncID.
private struct SyncFile: Codable {
    var deviceID: String
    var exportedAt: Date
    var categories: [CategoryDTO] = []
    var activities: [ActivityDTO] = []
    var sessions: [SessionDTO] = []
    var scheduleBlocks: [ScheduleBlockDTO] = []
    var tombstones: [TombstoneDTO] = []
}

private struct CategoryDTO: Codable {
    var syncID: UUID; var name: String; var colorHex: String
    var sortOrder: Int; var createdAt: Date; var isArchived: Bool; var updatedAt: Date
}
private struct ActivityDTO: Codable {
    var syncID: UUID; var name: String; var createdAt: Date; var isArchived: Bool
    var categorySyncID: UUID?; var updatedAt: Date
}
private struct SessionDTO: Codable {
    var syncID: UUID; var startedAt: Date; var endedAt: Date?
    var plannedMinutes: Int; var elapsedSeconds: Int; var pausedSeconds: Int
    var outcomeRaw: Int; var ratingRaw: Int; var note: String
    var activitySyncID: UUID?; var updatedAt: Date
}
private struct ScheduleBlockDTO: Codable {
    var syncID: UUID; var title: String; var startedAt: Date; var endedAt: Date
    var colorHex: String; var createdAt: Date; var updatedAt: Date
}
private struct TombstoneDTO: Codable {
    var syncID: UUID; var typeName: String; var deletedAt: Date
}

// MARK: - Service

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    private enum Keys {
        static let folder = "syncFolderPath"
        static let deviceID = "syncDeviceID"
        static let lastSync = "syncLastDate"
    }

    /// User-selected sync folder (a folder inside their own iCloud Drive/Dropbox/etc.).
    private(set) var folderPath: String? {
        didSet { UserDefaults.standard.set(folderPath, forKey: Keys.folder) }
    }
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false

    /// Distinct per-device id (never migrated) so each device owns one file.
    let deviceID: String

    var isConfigured: Bool { folderPath != nil }

    private init() {
        let defaults = UserDefaults.standard
        folderPath = defaults.string(forKey: Keys.folder)
        lastSync = defaults.object(forKey: Keys.lastSync) as? Date
        if let existing = defaults.string(forKey: Keys.deviceID) {
            deviceID = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Keys.deviceID)
            deviceID = fresh
        }
    }

    func setFolder(_ url: URL) {
        folderPath = url.path
        lastError = nil
    }

    func clearFolder() {
        folderPath = nil
    }

    /// Directory that holds every device's file, created under the chosen folder.
    private var syncDirectory: URL? {
        guard let folderPath else { return nil }
        return URL(fileURLWithPath: folderPath).appendingPathComponent("FocusSessionSync", isDirectory: true)
    }

    private var ownFileURL: URL? {
        syncDirectory?.appendingPathComponent("\(deviceID).json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Sync entry point

    /// Export local state, merge every device file back in, then re-export so the
    /// files converge. Runs on the main context (data volume is small).
    func syncNow(context: ModelContext) {
        guard let syncDirectory, let ownFileURL else {
            lastError = "No sync folder selected."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            try FileManager.default.createDirectory(at: syncDirectory, withIntermediateDirectories: true)

            SyncBackfill.run(context: context)

            // A) publish our current state so local edits participate in the merge
            try writeOwnFile(to: ownFileURL, context: context)

            // B) read every device file (ours included)
            let files = try readAllFiles(in: syncDirectory)

            // C+D) merge winners into the local store
            applyMerge(files, context: context)

            // E) re-export so our file reflects the merged result
            try writeOwnFile(to: ownFileURL, context: context)

            let now = Date.now
            lastSync = now
            UserDefaults.standard.set(now, forKey: Keys.lastSync)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Export

    private func writeOwnFile(to url: URL, context: ModelContext) throws {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        let blocks = (try? context.fetch(FetchDescriptor<ScheduleBlock>())) ?? []
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []

        var file = SyncFile(deviceID: deviceID, exportedAt: .now)
        file.categories = categories.compactMap { c in
            guard let sid = c.syncID else { return nil }
            return CategoryDTO(syncID: sid, name: c.name, colorHex: c.colorHex,
                               sortOrder: c.sortOrder, createdAt: c.createdAt,
                               isArchived: c.isArchived, updatedAt: c.updatedAt ?? c.createdAt)
        }
        file.activities = activities.compactMap { a in
            guard let sid = a.syncID else { return nil }
            return ActivityDTO(syncID: sid, name: a.name, createdAt: a.createdAt,
                               isArchived: a.isArchived, categorySyncID: a.category?.syncID,
                               updatedAt: a.updatedAt ?? a.createdAt)
        }
        file.sessions = sessions.compactMap { s in
            guard let sid = s.syncID else { return nil }
            return SessionDTO(syncID: sid, startedAt: s.startedAt, endedAt: s.endedAt,
                              plannedMinutes: s.plannedMinutes, elapsedSeconds: s.elapsedSeconds,
                              pausedSeconds: s.pausedSeconds, outcomeRaw: s.outcomeRaw,
                              ratingRaw: s.ratingRaw, note: s.note,
                              activitySyncID: s.activity?.syncID, updatedAt: s.updatedAt ?? s.endedAt ?? s.startedAt)
        }
        file.scheduleBlocks = blocks.compactMap { b in
            guard let sid = b.syncID else { return nil }
            return ScheduleBlockDTO(syncID: sid, title: b.title, startedAt: b.startedAt,
                                    endedAt: b.endedAt, colorHex: b.colorHex,
                                    createdAt: b.createdAt, updatedAt: b.updatedAt ?? b.createdAt)
        }
        file.tombstones = tombstones.map {
            TombstoneDTO(syncID: $0.syncID, typeName: $0.typeName, deletedAt: $0.deletedAt)
        }

        let data = try Self.encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Read

    private func readAllFiles(in directory: URL) throws -> [SyncFile] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []

        var result: [SyncFile] = []
        for url in urls {
            // If the file lives in iCloud Drive it may be an evicted placeholder;
            // ask for a download and skip this round if it isn't materialized yet.
            if url.lastPathComponent.hasPrefix(".") { continue }
            if !fm.fileExists(atPath: url.path) {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let file = try? Self.decoder.decode(SyncFile.self, from: data) else { continue }
            result.append(file)
        }
        return result
    }

    // MARK: Merge

    private func applyMerge(_ files: [SyncFile], context: ModelContext) {
        // Latest deletion per syncID wins.
        var tombstones: [UUID: Date] = [:]
        for file in files {
            for t in file.tombstones {
                if let existing = tombstones[t.syncID], existing >= t.deletedAt { continue }
                tombstones[t.syncID] = t.deletedAt
            }
        }

        // Latest version per syncID wins, per type.
        var categoryWins: [UUID: CategoryDTO] = [:]
        var activityWins: [UUID: ActivityDTO] = [:]
        var sessionWins: [UUID: SessionDTO] = [:]
        var blockWins: [UUID: ScheduleBlockDTO] = [:]
        for file in files {
            for c in file.categories where isNewer(c.updatedAt, than: categoryWins[c.syncID]?.updatedAt) { categoryWins[c.syncID] = c }
            for a in file.activities where isNewer(a.updatedAt, than: activityWins[a.syncID]?.updatedAt) { activityWins[a.syncID] = a }
            for s in file.sessions where isNewer(s.updatedAt, than: sessionWins[s.syncID]?.updatedAt) { sessionWins[s.syncID] = s }
            for b in file.scheduleBlocks where isNewer(b.updatedAt, than: blockWins[b.syncID]?.updatedAt) { blockWins[b.syncID] = b }
        }

        // Index existing local records by syncID.
        var localCategories = indexBySyncID((try? context.fetch(FetchDescriptor<Category>())) ?? [])
        var localActivities = indexBySyncID((try? context.fetch(FetchDescriptor<Activity>())) ?? [])
        var localSessions = indexBySyncID((try? context.fetch(FetchDescriptor<FocusSession>())) ?? [])
        var localBlocks = indexBySyncID((try? context.fetch(FetchDescriptor<ScheduleBlock>())) ?? [])

        // Categories first, then activities (need category), then sessions (need activity).
        for (sid, dto) in categoryWins {
            if deleted(sid, dto.updatedAt, tombstones) { continue }
            let model = localCategories[sid] ?? {
                let c = Category(name: dto.name, colorHex: dto.colorHex, sortOrder: dto.sortOrder, createdAt: dto.createdAt)
                c.syncID = sid; context.insert(c); localCategories[sid] = c; return c
            }()
            guard (model.updatedAt ?? .distantPast) <= dto.updatedAt else { continue }
            model.name = dto.name; model.colorHex = dto.colorHex; model.sortOrder = dto.sortOrder
            model.createdAt = dto.createdAt; model.isArchived = dto.isArchived; model.updatedAt = dto.updatedAt
        }

        for (sid, dto) in activityWins {
            if deleted(sid, dto.updatedAt, tombstones) { continue }
            let model = localActivities[sid] ?? {
                let a = Activity(name: dto.name, category: nil, createdAt: dto.createdAt)
                a.syncID = sid; context.insert(a); localActivities[sid] = a; return a
            }()
            guard (model.updatedAt ?? .distantPast) <= dto.updatedAt else { continue }
            model.name = dto.name; model.createdAt = dto.createdAt; model.isArchived = dto.isArchived
            model.category = dto.categorySyncID.flatMap { localCategories[$0] }
            model.updatedAt = dto.updatedAt
        }

        for (sid, dto) in sessionWins {
            if deleted(sid, dto.updatedAt, tombstones) { continue }
            let model = localSessions[sid] ?? {
                let s = FocusSession(startedAt: dto.startedAt, endedAt: dto.endedAt,
                                     plannedMinutes: dto.plannedMinutes, elapsedSeconds: dto.elapsedSeconds,
                                     outcome: .endedEarly, activity: nil)
                s.syncID = sid; context.insert(s); localSessions[sid] = s; return s
            }()
            guard (model.updatedAt ?? .distantPast) <= dto.updatedAt else { continue }
            model.startedAt = dto.startedAt; model.endedAt = dto.endedAt
            model.plannedMinutes = dto.plannedMinutes; model.elapsedSeconds = dto.elapsedSeconds
            model.pausedSeconds = dto.pausedSeconds; model.outcomeRaw = dto.outcomeRaw
            model.ratingRaw = dto.ratingRaw; model.note = dto.note
            model.activity = dto.activitySyncID.flatMap { localActivities[$0] }
            model.updatedAt = dto.updatedAt
        }

        for (sid, dto) in blockWins {
            if deleted(sid, dto.updatedAt, tombstones) { continue }
            let model = localBlocks[sid] ?? {
                let b = ScheduleBlock(title: dto.title, startedAt: dto.startedAt, endedAt: dto.endedAt, colorHex: dto.colorHex)
                b.syncID = sid; context.insert(b); localBlocks[sid] = b; return b
            }()
            guard (model.updatedAt ?? .distantPast) <= dto.updatedAt else { continue }
            model.title = dto.title; model.startedAt = dto.startedAt; model.endedAt = dto.endedAt
            model.colorHex = dto.colorHex; model.createdAt = dto.createdAt; model.updatedAt = dto.updatedAt
        }

        // Persist every tombstone locally so deletions keep propagating even if
        // the device that first deleted the record later leaves the folder.
        let knownTombstones = Set(((try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []).map(\.syncID))
        for (sid, deletedAt) in tombstones where !knownTombstones.contains(sid) {
            context.insert(SyncTombstone(syncID: sid, typeName: "", deletedAt: deletedAt))
        }

        // Apply deletions: remove any local record a newer tombstone covers.
        for (sid, deletedAt) in tombstones {
            if let m = localCategories[sid], (m.updatedAt ?? .distantPast) <= deletedAt { context.delete(m) }
            if let m = localActivities[sid], (m.updatedAt ?? .distantPast) <= deletedAt { context.delete(m) }
            if let m = localSessions[sid], (m.updatedAt ?? .distantPast) <= deletedAt { context.delete(m) }
            if let m = localBlocks[sid], (m.updatedAt ?? .distantPast) <= deletedAt { context.delete(m) }
        }

        // Plain save: merge must NOT re-stamp updatedAt or create new tombstones.
        try? context.save()
    }

    private func isNewer(_ candidate: Date, than current: Date?) -> Bool {
        guard let current else { return true }
        return candidate >= current
    }

    private func deleted(_ sid: UUID, _ updatedAt: Date, _ tombstones: [UUID: Date]) -> Bool {
        guard let deletedAt = tombstones[sid] else { return false }
        return deletedAt >= updatedAt
    }

    private func indexBySyncID<T: PersistentModel & SyncTracked>(_ rows: [T]) -> [UUID: T] {
        var dict: [UUID: T] = [:]
        for row in rows { if let sid = row.syncID { dict[sid] = row } }
        return dict
    }
}
