import Foundation
import SwiftData

/// A non-focus block shown on the timetable for context — a meeting, class,
/// break, or anything you want to see alongside your focus. It is NOT a focus
/// session: excluded from stats, streaks, and the community entirely.
@Model
final class ScheduleBlock {
    var title: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date = Date.now
    var colorHex: String = "#8E8E93"
    var createdAt: Date = Date.now
    var syncID: UUID?               // portable id for cross-device folder sync
    var updatedAt: Date?            // last local mutation (optional so old stores migrate lightly)

    var durationSeconds: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }

    init(title: String, startedAt: Date, endedAt: Date, colorHex: String) {
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.colorHex = colorHex
    }
}
