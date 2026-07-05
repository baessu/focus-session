import Foundation
import Observation

/// Wall-clock-anchored focus timer. The persisted truth is `elapsed`, derived
/// from real timestamps (not tick counts), so it stays correct across sleep/wake.
/// The async ticker only refreshes the display ~4x/second.
@MainActor
@Observable
final class FocusTimerEngine {
    /// Shared instance so the main window and the menu-bar timer stay in sync.
    static let shared = FocusTimerEngine()

    enum Phase: Equatable { case idle, running, paused }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0   // focused seconds, paused gaps excluded

    // User input (bound from the setup card)
    var taskName: String = ""
    var plannedMinutes: Int = 25

    // Fires once when elapsed first crosses the planned duration (notification hook).
    var onPlannedReached: (() -> Void)?

    private var segmentStart: Date?          // wall-clock start of the current running segment
    private var sessionStartedAt: Date?      // wall-clock start of the whole session
    private var accumulated: TimeInterval = 0 // focused time from completed segments
    private var didReachPlanned = false
    private var tickTask: Task<Void, Never>?

    var startedAt: Date? { sessionStartedAt }
    var planned: TimeInterval { TimeInterval(max(0, plannedMinutes) * 60) }
    var remaining: TimeInterval { max(0, planned - elapsed) }
    var isOvertime: Bool { phase != .idle && planned > 0 && elapsed >= planned }
    var progress: Double { planned <= 0 ? 0 : min(1, elapsed / planned) }
    var canStart: Bool { plannedMinutes > 0 }

    // Display string: counts down while focusing, counts up once in overtime.
    var displayTime: String {
        isOvertime ? "+" + formatClock(elapsed - planned) : formatClock(remaining)
    }

    func start() {
        guard phase == .idle, canStart else { return }
        accumulated = 0
        elapsed = 0
        didReachPlanned = false
        let now = Date()
        sessionStartedAt = now
        segmentStart = now
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running else { return }
        commitSegment()
        phase = .paused
        stopTicker()
    }

    func resume() {
        guard phase == .paused else { return }
        segmentStart = Date()
        phase = .running
        startTicker()
    }

    /// Ends the session and returns the result. Resets the engine to idle.
    func end() -> SessionResult {
        commitSegment()
        let now = Date()
        let result = SessionResult(
            taskName: taskName.trimmingCharacters(in: .whitespacesAndNewlines),
            plannedMinutes: plannedMinutes,
            focusedSeconds: Int(elapsed.rounded()),
            reachedPlanned: didReachPlanned,
            startedAt: sessionStartedAt ?? now,
            endedAt: now
        )
        reset()
        return result
    }

    func reset() {
        stopTicker()
        phase = .idle
        elapsed = 0
        accumulated = 0
        segmentStart = nil
        sessionStartedAt = nil
        didReachPlanned = false
    }

    private func commitSegment() {
        if let start = segmentStart {
            accumulated += Date().timeIntervalSince(start)
            segmentStart = nil
        }
        elapsed = accumulated
    }

    private func tick() {
        if let start = segmentStart {
            elapsed = accumulated + Date().timeIntervalSince(start)
        }
        if !didReachPlanned && planned > 0 && elapsed >= planned {
            didReachPlanned = true
            onPlannedReached?()
        }
    }

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }
}
