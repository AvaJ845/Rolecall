import Foundation

/// Turns the reader's tracked applications into a file they can keep. Free — it's their
/// own data. Markdown for a human, CSV for a spreadsheet.
enum ApplicationExport {

    static func markdown(_ entries: [(role: Role, application: Application)]) -> String {
        var out = "# Rolecall — my applications\n\n"
        out += "_\(entries.count) tracked · exported \(df.string(from: Date()))_\n\n"
        out += "| Company | Role | Stage | Applied | Updated | Link |\n"
        out += "|---|---|---|---|---|---|\n"
        for e in entries.sorted(by: { $0.application.updatedOn > $1.application.updatedOn }) {
            out += "| \(md(e.role.company)) | \(md(e.role.title)) | \(e.application.stage.label) "
            out += "| \(day(e.application.appliedOn)) | \(day(e.application.updatedOn)) "
            out += "| \(e.role.url.absoluteString) |\n"
            if !e.application.note.isEmpty {
                out += "\n> \(e.application.note.replacingOccurrences(of: "\n", with: " "))\n"
            }
        }
        return out
    }

    static func csv(_ entries: [(role: Role, application: Application)]) -> String {
        var rows = ["company,role,stage,applied,updated,note,url"]
        for e in entries.sorted(by: { $0.application.updatedOn > $1.application.updatedOn }) {
            rows.append([
                e.role.company, e.role.title, e.application.stage.label,
                day(e.application.appliedOn), day(e.application.updatedOn),
                e.application.note, e.role.url.absoluteString,
            ].map(csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Write both to the caches dir and return the URLs, for a ShareLink.
    static func files(_ entries: [(role: Role, application: Application)]) -> [URL] {
        let dir = FileManager.default.temporaryDirectory
        let md = dir.appendingPathComponent("rolecall-applications.md")
        let csvURL = dir.appendingPathComponent("rolecall-applications.csv")
        try? markdown(entries).data(using: .utf8)?.write(to: md)
        try? csv(entries).data(using: .utf8)?.write(to: csvURL)
        return [md, csvURL]
    }

    // MARK: helpers

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    private static func day(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .omitted)
    }

    private static func md(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
