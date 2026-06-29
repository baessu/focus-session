import Foundation

/// How a focus session concluded. Stored as Int on FocusSession for predicate safety.
enum SessionOutcome: Int, Sendable, CaseIterable {
    case completed = 0      // reached the planned duration
    case endedEarly = 1     // ended before the planned duration
    case abandonedIdle = 2  // left running well past planned with no end (excluded from stats by default)
}
