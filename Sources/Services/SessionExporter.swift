import AppKit
import UniformTypeIdentifiers

@MainActor
enum SessionExporter {
    static func exportCSV(_ sessions: [FocusSession]) {
        let header = "Date,Start,End,Task,Category,Minutes,Focus,Note"
        let dateFmt = Date.FormatStyle.dateTime.year().month(.twoDigits).day(.twoDigits)
        let timeFmt = Date.FormatStyle.dateTime.hour().minute()

        var rows = [header]
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let fields = [
                s.startedAt.formatted(dateFmt),
                s.startedAt.formatted(timeFmt),
                (s.endedAt ?? s.startedAt).formatted(timeFmt),
                s.activity?.name ?? "Untitled",
                s.activity?.category?.name ?? "Uncategorized",
                String(format: "%.1f", Double(s.elapsedSeconds) / 60),
                s.rating.label,
                s.note,
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }

        let csv = rows.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "focus-sessions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
