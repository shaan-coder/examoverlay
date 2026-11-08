import CoreGraphics
import Foundation

enum Auto {
    static func dwell(chars: Int, confidence: Double) -> Double {
        let base: Double
        switch (chars, confidence) {
        case (..<700, 0.9...): base = 8
        case (..<1200, 0.8...): base = 14
        case (..<1800, 0.7...): base = 24
        default: base = 42
        }
        return base * Double.random(in: 0.7...1.3)
    }

    static func arc(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let mx = (a.x + b.x) / 2
        let my = (a.y + b.y) / 2
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let off = Double.random(in: -18...18)
        return CGPoint(x: mx - dy / len * off, y: my + dx / len * off)
    }

    static func pauseEvery(_ step: Int) -> Bool {
        step > 0 && step % Int.random(in: 6...10) == 0
    }

    static func decoy(than: String?, letters: [String]) -> String? {
        let pool = letters.filter { $0 != than }
        guard pool.count > 1 else { return pool.first }
        return pool.randomElement()
    }

    static func wantsWrong(confidence: Double, isLast: Bool) -> Bool {
        guard !isLast, confidence < 0.95 else { return false }
        return Double.random(in: 0...1) < 0.25
    }

    static let advance = ["next", "continue", "next question", "forward", "proceed", "next page"]
    static let submit = ["submit", "finish", "turn in", "submit test", "end test", "submit answers"]
    static let back = ["back", "previous", "prev"]

    static func button(_ boxes: [(String, CGRect)], _ words: [String]) -> CGRect? {
        for (t, b) in boxes {
            let l = t.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if words.contains(where: { l == $0 || l.hasPrefix($0 + " ") }) { return b }
        }
        return nil
    }

    static func blank(_ boxes: [(String, CGRect)], below y: CGFloat) -> CGRect? {
        boxes.filter {
            $0.1.minY > y && $0.0.trimmingCharacters(in: .whitespaces).count < 3
        }.map(\.1).first
    }

    static func wrongLetter(than: String?, options: Int) -> String? {
        let all = Array(Resolve.letters.prefix(max(0, options)))
        let pool = all.filter { $0 != than }
        return pool.randomElement()
    }
}
