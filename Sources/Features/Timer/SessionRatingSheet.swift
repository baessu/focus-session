import SwiftUI

/// Shown when a session ends: rate how focused it felt and add an optional note.
struct SessionRatingSheet: View {
    let result: SessionResult
    var accent: Color
    var onSave: (FocusRating, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: FocusRating = .neutral
    @State private var note: String = ""

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Session complete").font(.headline)
                Text("\(result.taskName.isEmpty ? "Untitled" : result.taskName) · \(formatDurationShort(seconds: result.focusedSeconds))")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ForEach([FocusRating.distracted, .neutral, .focused]) { r in
                    Button { rating = r } label: {
                        VStack(spacing: 6) {
                            Text(r.emoji).font(.system(size: 30))
                            Text(r.label).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(rating == r ? accent.opacity(0.18) : Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(rating == r ? accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Note (optional)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.callout)
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
            }

            Button { onSave(rating, note); dismiss() } label: {
                Text("Save").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .padding(20)
        .frame(width: 360)
    }
}
