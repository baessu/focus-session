import SwiftUI

/// How focused a session felt, set by the user when ending it.
enum FocusRating: Int, Sendable, CaseIterable, Identifiable {
    case distracted = 0
    case neutral = 1
    case focused = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .focused: return "Focused"
        case .neutral: return "Okay"
        case .distracted: return "Distracted"
        }
    }

    /// Number of filled signal bars (1...3).
    var level: Int { rawValue + 1 }

    /// Semantic tint for the level.
    var tint: Color {
        switch self {
        case .distracted: return .red
        case .neutral: return .orange
        case .focused: return .green
        }
    }
}

/// Signal-bar gauge (1–3 bars filled) representing a focus rating — reads as an
/// intensity level at a glance and keeps the same visual language everywhere.
struct FocusBars: View {
    let rating: FocusRating
    var barWidth: CGFloat = 4
    var maxHeight: CGFloat = 18
    var spacing: CGFloat = 3

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < rating.level ? rating.tint : Color.primary.opacity(0.15))
                    .frame(width: barWidth, height: maxHeight * CGFloat(i + 1) / 3)
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
    }
}
