import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make() throws -> ModelContainer {
        let schema = Schema([Category.self, Activity.self, FocusSession.self, ScheduleBlock.self, SyncTombstone.self])
        let storeURL = stableStoreURL()
        try prepareStore(at: storeURL)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func stableStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        if appSupport.path.contains("/Library/Containers/com.baessu.focussession/Data/") {
            return appSupport.appendingPathComponent("default.store")
        }

        return fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.baessu.focussession/Data/Library/Application Support/default.store")
    }

    private static func prepareStore(at stableURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: stableURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let bestExisting = candidateStoreURLs(stableURL: stableURL)
            .filter { $0.path != stableURL.path }
            .max { totalStoreBytes($0) < totalStoreBytes($1) }

        guard let bestExisting, totalStoreBytes(bestExisting) > totalStoreBytes(stableURL) else { return }
        try replaceStore(at: stableURL, with: bestExisting)
    }

    private static func candidateStoreURLs(stableURL: URL) -> [URL] {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            stableURL,
            appSupport.appendingPathComponent("default.store"),
            appSupport.appendingPathComponent("com.baessu.focussession/default.store"),
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.baessu.focussession/Data/Library/Application Support/default.store")
        ]
    }

    private static func totalStoreBytes(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        return ["", "-wal", "-shm"].reduce(0) { total, suffix in
            let file = URL(fileURLWithPath: url.path + suffix)
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let size = attrs[.size] as? NSNumber else {
                return total
            }
            return total + size.uint64Value
        }
    }

    private static func replaceStore(at target: URL, with source: URL) throws {
        let fm = FileManager.default
        let backupSuffix = ".backup-\(Int(Date().timeIntervalSince1970))"

        for suffix in ["", "-wal", "-shm"] {
            let old = URL(fileURLWithPath: target.path + suffix)
            if fm.fileExists(atPath: old.path) {
                try fm.moveItem(at: old, to: URL(fileURLWithPath: old.path + backupSuffix))
            }
        }

        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            let to = URL(fileURLWithPath: target.path + suffix)
            if fm.fileExists(atPath: from.path) {
                try fm.copyItem(at: from, to: to)
            }
        }
    }
}
