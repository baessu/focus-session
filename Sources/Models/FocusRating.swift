import Foundation

/// How focused a session felt, set by the user when ending it.
enum FocusRating: Int, Sendable, CaseIterable, Identifiable {
    case distracted = 0
    case neutral = 1
    case focused = 2

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .focused: return "🤩"
        case .neutral: return "🙂"
        case .distracted: return "😔"
        }
    }

    var label: String {
        switch self {
        case .focused: return "Focused"
        case .neutral: return "Okay"
        case .distracted: return "Distracted"
        }
    }

    var arrow: String {
        switch self {
        case .focused: return "arrow.up"
        case .neutral: return "arrow.right"
        case .distracted: return "arrow.down"
        }
    }
}
