import SwiftUI
import SwiftData

/// A prior task the field can suggest, carrying its project (category) so the
/// caller can auto-assign it on selection.
struct TaskSuggestion: Identifiable, Hashable {
    let name: String
    let categoryID: PersistentIdentifier?
    let categoryName: String?
    let colorHex: String?

    var id: String { "\(name)#\(categoryName ?? "")" }
}

/// A text field that suggests matching prior task names (with their project
/// chip) while typing, so the user can reuse a task and its project in one tap.
struct SuggestingTextField: View {
    @Binding var text: String
    var placeholder: String
    var suggestions: [TaskSuggestion]
    /// `true` uses the big centered setup-card look; `false` a rounded-border field.
    var large: Bool = false
    /// Subtle background fill that blends into the card, instead of a bordered box.
    var filled: Bool = false
    /// Center the text (used on the active timer).
    var centered: Bool = false
    var onSelect: (TaskSuggestion) -> Void = { _ in }

    @FocusState private var focused: Bool
    @State private var showList = false
    @State private var fieldHeight: CGFloat = 0

    private var matches: [TaskSuggestion] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }   // only suggest once the user starts typing
        var seen = Set<String>()
        let filtered = suggestions.filter { s in
            let n = s.name.lowercased()
            guard n != q, n.contains(q), !seen.contains(s.id) else { return false }
            seen.insert(s.id)
            return true
        }
        return Array(filtered.prefix(6))
    }

    var body: some View {
        field
            .focused($focused)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldHeight = $0 }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    showList = true
                } else {
                    // Keep the list briefly so a click on a row still registers.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { showList = false }
                }
            }
            .overlay(alignment: .topLeading) {
                if showList && !matches.isEmpty {
                    dropdown.offset(y: fieldHeight + 4)
                }
            }
            .zIndex(1)
    }

    @ViewBuilder private var field: some View {
        if large {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
        } else if filled {
            // Blends into the card: no bright bordered box, just a subtle fill.
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .multilineTextAlignment(centered ? .center : .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var dropdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                Button {
                    text = item.name
                    onSelect(item)
                    focused = false
                    showList = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(item.name).lineLimit(1)
                        Spacer(minLength: 8)
                        if let category = item.categoryName {
                            projectChip(category, colorHex: item.colorHex)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < matches.count - 1 { Divider() }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private func projectChip(_ name: String, colorHex: String?) -> some View {
        let color = Color(hex: colorHex ?? "#8E8E93")
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(color.opacity(0.14), in: .capsule)
    }
}
