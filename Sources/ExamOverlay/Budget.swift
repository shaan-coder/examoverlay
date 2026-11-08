import Foundation

actor Budget {
    static let shared = Budget()
    private var events: [(Date, Int)] = []
    private var last = Date.distantPast
    private let gap: TimeInterval = 11
    private let cap = 7000
    private let window: TimeInterval = 62

    func reserve(_ tokens: Int) async {
        let since = Date().timeIntervalSince(last)
        if since < gap { try? await Task.sleep(nanoseconds: UInt64((gap - since) * 1_000_000_000)) }
        while true {
            let now = Date()
            events.removeAll { now.timeIntervalSince($0.0) > window }
            let used = events.reduce(0) { $0 + $1.1 }
            if used + tokens <= cap {
                events.append((now, tokens))
                last = now
                return
            }
            let oldest = events.first?.0 ?? now
            let wait = max(0.5, window - now.timeIntervalSince(oldest))
            try? await Task.sleep(nanoseconds: UInt64(min(wait, 20) * 1_000_000_000))
        }
    }
}
