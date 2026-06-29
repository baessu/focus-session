import SwiftUI

extension Color {
    /// Creates a Color from a "#RRGGBB" hex string. Falls back to indigo on bad input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = Color(.sRGB, red: 0.39, green: 0.40, blue: 0.95)
            return
        }
        self = Color(
            .sRGB,
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

/// The default category palette, used for seeding and the color picker.
enum CategoryPalette {
    static let swatches: [String] = [
        "#6366F1", // indigo
        "#10B981", // emerald
        "#F59E0B", // amber
        "#EC4899", // pink
        "#3B82F6", // blue
        "#8B5CF6", // violet
        "#EF4444", // red
        "#14B8A6", // teal
    ]
}
