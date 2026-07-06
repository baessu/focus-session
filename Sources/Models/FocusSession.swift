import Foundation
import SwiftData

/// One completed (or abandoned) focus session — the unit of accumulated history.
/// `elapsedSeconds` is the persisted truth, derived from wall-clock timestamps.
@Model
final class FocusSession {
    var startedAt: Date = Date.now
    var endedAt: Date?              // nil == still running
    var plannedMinutes: Int = 25
    var elapsedSeconds: Int = 0     // focused seconds, paused gaps excluded
    var pausedSeconds: Int = 0      // present from v1 so pause/resume stays a lightweight migration
    var outcomeRaw: Int = 0
    var ratingRaw: Int = 1          // focus quality: 0 distracted, 1 neutral, 2 focused
    var note: String = ""
    var publicID: UUID?             // stable id for the community summary (upsert/delete)

    var activity: Activity?

    /// Bridges the stored Int to the typed enum (not persisted itself).
    var outcome: SessionOutcome {
        get { SessionOutcome(rawValue: outcomeRaw) ?? .endedEarly }
        set { outcomeRaw = newValue.rawValue }
    }

    var rating: FocusRating {
        get { FocusRating(rawValue: ratingRaw) ?? .neutral }
        set { ratingRaw = newValue.rawValue }
    }

    init(
        startedAt: Date,
        endedAt: Date?,
        plannedMinutes: Int,
        elapsedSeconds: Int,
        outcome: SessionOutcome,
        activity: Activity?
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
        self.elapsedSeconds = elapsedSeconds
        self.outcomeRaw = outcome.rawValue
        self.activity = activity
    }
}
