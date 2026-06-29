import SwiftUI

/// A chronological journal of sessions in the active range, grouped by day.
struct SessionTimeline: View {
    let sessions: [FocusSession]      // ascending by startedAt
    var notesOnly: Bool = false

    private var visible: [FocusSession] {
        notesOnly ? sessions.filter { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : sessions
    }

    var body: some View {
        let grouped = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.startedAt) }
        let days = grouped.keys.sorted(by: >)

        LazyVStack(alignment: .leading, spacing: 22) {
            if days.isEmpty {
                Text(notesOnly ? "No notes in this range" : "No sessions in this range")
                    .font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(.subheadline.weight(.semibold))
                    ForEach(grouped[day]!.sorted { $0.startedAt > $1.startedAt }) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: FocusSession

    private var color: Color { Color(hex: session.activity?.category?.colorHex ?? "#8E8E93") }
    private var trimmedNote: String { session.note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.activity?.name ?? "Untitled")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let cat = session.activity?.category {
                        HStack(spacing: 5) {
                            Circle().fill(color).frame(width: 7, height: 7)
                            Text(cat.name).font(.caption2)
                        }
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background(color.opacity(0.16), in: .capsule)
                    }
                    Spacer(minLength: 4)
                    Text(session.rating.emoji).font(.caption)
                }

                HStack {
                    Text("\(timeStr(session.startedAt)) → \(timeStr(session.endedAt ?? session.startedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDurationShort(seconds: session.elapsedSeconds))
                        .font(.caption.weight(.medium).monospacedDigit())
                }

                if !trimmedNote.isEmpty {
                    Text(trimmedNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.top, 1)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 9))
    }

    private func timeStr(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }
}
