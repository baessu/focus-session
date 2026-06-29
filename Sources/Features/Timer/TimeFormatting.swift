import Foundation

/// Formats a focus duration as mm:ss, or H:MM:SS once it crosses an hour.
func formatClock(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%02d:%02d", m, s)
}

/// Compact "1h 25m" / "25m" style for history and stats labels.
func formatDurationShort(seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    if m > 0 { return "\(m)m" }
    return "\(seconds)s"
}
