import Foundation
import SwiftData

/// A thing the user focuses on (the "task"). Named Activity to avoid clashing
/// with Swift's `Task`. Belongs to a Category; owns its focus sessions.
@Model
final class Activity {
    var name: String = ""
    var createdAt: Date = Date.now
    var isArchived: Bool = false
    var syncID: UUID?               // portable id for cross-device folder sync
    var updatedAt: Date?            // last local mutation (optional so old stores migrate lightly)

    var category: Category?

    @Relationship(deleteRule: .cascade, inverse: \FocusSession.activity)
    var sessions: [FocusSession] = []

    init(name: String, category: Category? = nil, createdAt: Date = .now) {
        self.name = name
        self.category = category
        self.createdAt = createdAt
    }
}
