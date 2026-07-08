import Foundation
import SwiftData

/// Records that a record was deleted, so folder sync can propagate the deletion
/// across devices instead of a stale replica resurrecting it.
@Model
final class SyncTombstone {
    var syncID: UUID = UUID()
    var typeName: String = ""       // "FocusSession", "Category", … (informational)
    var deletedAt: Date = Date.now

    init(syncID: UUID, typeName: String, deletedAt: Date = .now) {
        self.syncID = syncID
        self.typeName = typeName
        self.deletedAt = deletedAt
    }
}

/// Every model that participates in cross-device folder sync carries a portable
/// `syncID` and an `updatedAt` used for last-writer-wins merging.
protocol SyncTracked: AnyObject {
    var syncID: UUID? { get set }
    var updatedAt: Date? { get set }
}

extension Category: SyncTracked {}
extension Activity: SyncTracked {}
extension FocusSession: SyncTracked {}
extension ScheduleBlock: SyncTracked {}

extension ModelContext {
    /// Saves while keeping sync metadata current: every inserted/changed tracked
    /// record gets a fresh `updatedAt`, and every deleted one leaves a tombstone.
    /// Use this in place of `save()` for any user-facing mutation.
    func saveSynced() {
        let now = Date.now

        for model in insertedModelsArray + changedModelsArray {
            guard let tracked = model as? any SyncTracked else { continue }
            if tracked.syncID == nil { tracked.syncID = UUID() }
            tracked.updatedAt = now
        }

        for model in deletedModelsArray {
            guard let tracked = model as? any SyncTracked, let sid = tracked.syncID else { continue }
            insert(SyncTombstone(syncID: sid, typeName: String(describing: type(of: model)), deletedAt: now))
        }

        try? save()
    }
}

/// One-time backfill so records created before sync existed get a `syncID`.
enum SyncBackfill {
    @MainActor
    static func run(context: ModelContext) {
        assign(context, FetchDescriptor<Category>())
        assign(context, FetchDescriptor<Activity>())
        assign(context, FetchDescriptor<FocusSession>())
        assign(context, FetchDescriptor<ScheduleBlock>())
        try? context.save()
    }

    @MainActor
    private static func assign<T: PersistentModel & SyncTracked>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) {
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows where row.syncID == nil {
            row.syncID = UUID()
        }
    }
}
