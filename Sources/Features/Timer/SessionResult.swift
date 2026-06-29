import Foundation

/// Value type returned by the engine when a session ends.
/// In M2 it is logged; in M3 it becomes a persisted FocusSession row.
struct SessionResult: Sendable, Equatable, Identifiable {
    let id = UUID()
    let taskName: String
    let plannedMinutes: Int
    let focusedSeconds: Int
    let reachedPlanned: Bool
    let startedAt: Date
    let endedAt: Date
}
