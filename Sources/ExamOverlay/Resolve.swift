import CoreGraphics
import Foundation

/// Turns a model answer into a screen rectangle. Text match first, letter
/// second. Labels are detected only as a consecutive, left-aligned run that
/// starts at A, so tab titles and sidebar entries never qualify.
enum Resolve {
    static let letters = ["A", "B", "C", "D", "E", "F"]

    static func index(_ letter: String) -> Int? {
        letters.firstIndex(of: letter.uppercased())
    }

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

    /// Text rows in the lower 55% of the page, for positional fallback.
    static func rows(_ boxes: [(String, CGRect)]) -> [CGRect] {
        let top = boxes.map { $0.1.minY }.min() ?? 0
        let bottom = boxes.map { $
