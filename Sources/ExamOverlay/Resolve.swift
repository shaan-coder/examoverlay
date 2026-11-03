import CoreGraphics
import Foundation

/// Turns a model answer into a screen rectangle. Text match first, letter
/// second. Labels are only accepted as a consecutive, left-aligned run that
/// starts at A, so tab titles and sidebar entries never qualify.
enum Resolve {
    static let letters = ["A", "B", "C", "D", "E", "F"]

    static func index(_ letter: String) -> Int? { letters.firstIndex(of: letter.uppercased()) }

    static func markerLetter(_ raw: String) -> String? {
        let t = raw.uppercased()
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "8", with: "B")
            .trimmingCharacters(in: .whitespaces)
        guard let f = t.first, letters.contains(String(f)) else { return nil }
        let rest = t.dropFirst()
        guard let n = rest.first else { return String(f) }
        if ".):-".contains(n) { return String(f) }
        if n == " " && t.count < 40 { return String(f) }
        return nil
    }

    static func labels(_ boxes: [(String, CGRect)]) -> [(String, CGRect)] {
        let marked = boxes.compactMap { b -> (String, CGRect)? in
            markerLetter(b.0).map { ($0, b.1) }
        }.sorted { $0.1.minY < $1.1.minY }

        var runs: [[(String, CGRect)]] = []
        var cur: [(String, CGRect)] = []
        for m in marked {
            if m.0 == "A" {
                if !cur.isEmpty { runs.append(cur) }
                cur = [m]
            } else if let p = cur.last, m.0 == letters[min(cur.count, 5)],
                      abs(m.1.minX - p.1.minX) < max(p.1.height, 12) * 12 {
                cur.append(m)
            } else if !cur.isEmpty {
                runs.append(cur)
                cur = []
            }
        }
        if !cur.isEmpty { runs.append(cur) }
        return runs.filter { $0.count >= 2 }.max { $0[0].1.minY < $1[0].1.minY } ?? []
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// Merged text rows in the lower 55% of the page, for positional fallback.
    static func rows(_ boxes: [(String, CGRect)]) -> [CGRect] {
        let top = boxes.map { $0.1.minY }.min() ?? 0
        let bottom = boxes.map { $0.1.maxY }.max() ?? 0
        let cut = top + (bottom - top) * 0.45
        let lower = boxes.filter { $0.1.midY > cut }.sorted { $0.1.minY < $1.1.minY }
        var out: [CGRect] = []
        for b in lower {
            if let l = out.last, b.1.minY - l.maxY < max(b.1.height, 8) * 0.9 {
                out[out.count - 1] = l.union(b.1)
            } else {
                out.append(b.1)
            }
        }
        return out
    }

    /// Letter implied by a box's position relative to the label run.
    static func letter(for box: CGRect, labels: [(String, CGRect)]) -> String? {
        let before = labels.enumerated().filter { $0.element.1.minY <= box.midY + 4 }
        guard let last = before.last else { return nil }
        return letters[min(last.offset, 5)]
    }

    struct Target {
        var box: CGRect
        var tier: String
        var text: String
    }

    static func target(answer: String, letter: String?, boxes: [(String, CGRect)]) -> Target? {
        let needle = normalize(answer.replacingOccurrences(
            of: #"^[A-Fa-f][\.\)]\s*"#, with: "", options: .regularExpression))

        if needle.count >= 3 {
            let hits = boxes.filter { normalize($0.0).contains(needle) }
            if let b = hits.max(by: { $0.1.minY < $1.1.minY }) {
                return Target(box: b.1, tier: "text", text: b.0)
            }
            let words = needle.split(separator: " ").filter { $0.count >= 4 }
            if !words.isEmpty {
                let need = max(1, words.count / 2)
                let scored = boxes.map { b -> ((String, CGRect), Int) in
                    let t = normalize(b.0)
                    return (b, words.filter { t.contains($0) }.count)
                }.filter { $0.1 >= need }
                 .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.1.minY > $1.0.1.minY }
                if let best = scored.first {
                    return Target(box: best.0.1, tier: "overlap\(best.1)", text: best.0.0)
                }
            }
        }

        guard let l = letter, let i = index(l) else { return nil }
        let labs = labels(boxes)
        if i < labs.count { return Target(box: labs[i].1, tier: "label", text: labs[i].0) }
        let rs = rows(boxes)
        if i < rs.count { return Target(box: rs[i], tier: "row", text: "") }
        if let last = rs.last { return Target(box: last, tier: "row-clamped", text: "") }
        return nil
    }
}
