import AppKit
import Foundation

enum StudyReport {

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func stem(_ raw: String) -> String {
        let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var picked: [String] = []
        for l in lines.reversed() {
            if l.isEmpty { continue }
            if l.range(of: #"^[A-Fa-f][\.\)]\s"#, options: .regularExpression) != nil { continue }
            if l.count < 12 { continue }
            picked.append(l)
            if picked.count == 2 { break }
        }
        return String(picked.reversed().joined(separator: " ").suffix(240))
    }

    @MainActor
    static func build() {
        let since = Calendar.current.startOfDay(for: Date())
        var seen = Set<String>()
        var rows: [(String, String, Double, String)] = []
        for o in AnswerLog.entries(since: since) {
            let a = (o["answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard a.count > 3 else { continue }
            let k = String(a.lowercased().prefix(60))
            if seen.contains(k) { continue }
            seen.insert(k)
            rows.append((o["letter"] as? String ?? "?",
                        a,
                        o["confidence"] as? Double ?? 0,
                        stem(o["q"] as? String ?? "")))
        }
        guard !rows.isEmpty else {
            let al = NSAlert()
            al.messageText = "Nothing to report"
            al.informativeText = "No answers recorded today."
            al.runModal()
            return
        }

        let avg = rows.map(\.2).reduce(0, +) / Double(rows.count)
        let shaky = rows.filter { $0.2 < 0.55 }.count

        var html = """
        <!doctype html><meta charset="utf-8">
        <title>Study report</title>
        <style>
        body{font:15px/1.6 -apple-system,Helvetica,sans-serif;max-width:820px;margin:40px auto;padding:0 24px;color:#111}
        h1{font-size:22px;margin-bottom:4px}.meta{color:#666;font-size:13px;margin-bottom:26px}
        .item{border-left:3px solid #ddd;padding:2px 0 2px 16px;margin-bottom:22px}
        .item.low{border-color:#e0a030}.item.mid{border-color:#bbb}
        .stem{color:#666;font-size:13px;margin-bottom:6px}
        .ans{font-weight:600}.tag{font:11px Menlo,monospace;color:#888;margin-left:8px}
        </style>
        <h1>Study report</h1>
        <div class="meta">\(rows.count) answers · average confidence \(Int(avg * 100))% · \(shaky) flagged</div>
        """
        for r in rows {
            let cls = r.2 < 0.55 ? "item low" : (r.2 < 0.8 ? "item mid" : "item")
            html += """
            <div class="\(cls)">
            <div class="stem">\(esc(r.3))</div>
            <div><span class="ans">\(esc(r.0)). \(esc(r.1))</span>
            <span class="tag">\(Int(r.2 * 100))%</span></div>
            </div>
            """
        }

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/ExamOverlay reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = dir.appendingPathComponent("report-\(stamp)-\(Int(Date().timeIntervalSince1970)).html")
        try? html.write(to: url, atomically: true, encoding: .utf8)
        Log.write("report \(url.lastPathComponent) rows=\(rows.count)")
        NSWorkspace.shared.open(url)
    }
}
