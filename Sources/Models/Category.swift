import Foundation
import SwiftData

/// A color-coded grouping for activities (e.g. "Deep Work", "Study").
@Model
final class Category {
    var name: String = ""
    var colorHex: String = "#6366F1"
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Activity.category)
    var activities: [Activity] = []

    init(name: String, colorHex: String, sortOrder: Int = 0, createdAt: Date = .now) {
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
