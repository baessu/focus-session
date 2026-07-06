import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make() throws -> ModelContainer {
        let schema = Schema([Category.self, Activity.self, FocusSession.self, ScheduleBlock.self])
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

        guard !fm.fileExists(atPath: stableURL.path) else { return }

        let legacyURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("default.store")
        guard fm.fileExists(atPath: legacyURL.path), legacyURL.path != stableURL.path else { return }

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacyURL.path + suffix)
            let target = URL(fileURLWithPath: stableURL.path + suffix)
            if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: source, to: target)
            }
        }
    }
}
