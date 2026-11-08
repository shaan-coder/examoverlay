import Foundation

let history = History()

actor History {
    private struct Entry { let q: String; let letter: String; let text: String; let reason: String }
    private var items: [Entry] = []
    private let cap = 3

    func add(_ q: String, _ letter: String, _ text: String, _ reason: String) {
        let qq = String(q.suffix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard qq.count > 12 else { return }
        if items.last?.q == qq { return }
        items.append(Entry(q: qq, letter: letter,
                           text: String(text.prefix(100)),
                           reason: String(reason.prefix(100))))
        if items.count > cap { items.removeFirst(items.count - cap) }
    }

    func clear() { items.removeAll() }

    func block() -> String {
        guard !items.isEmpty else { return "" }
        var out = "Earlier questions on this screen, already answered:\n"
        for (i, e) in items.enumerated() {
            let label = e.letter.isEmpty ? "" : "\(e.letter). "
            out += "\(i + 1). Q: \(e.q)\n   Answered: \(label)\(e.text)\(e.reason.isEmpty ? "" : " (\(e.reason))")\n"
        }
        if out.count > 620 { out = String(out.prefix(620)) + "\n" }
        return out + "Use these as context only; the current question governs. Correct an earlier answer if it was wrong.\n\n"
    }
}
