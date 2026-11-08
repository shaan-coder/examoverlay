import Foundation

actor Health {
    static let shared = Health()
    private var fails: [String: (count: Int, until: Date)] = [:]

    private func host(_ url: URL?) -> String { url?.host ?? "unknown" }

    func usable(_ url: URL?) -> Bool {
        guard let e = fails[host(url)] else { return true }
        return Date() > e.until
    }

    func mark(_ url: URL?, ok: Bool) {
        let h = host(url)
        if ok { fails[h] = (0, .distantPast); return }
        let n = (fails[h]?.count ?? 0) + 1
        fails[h] = (n, n >= 3 ? Date().addingTimeInterval(300) : .distantPast)
        if n >= 3 { Log.write("health: \(h) benched 5m") }
    }

    func report() -> [(String, String)] {
        fails.map { h, e in
            let s = Date() > e.until ? "ok" : "benched \(Int(e.until.timeIntervalSinceNow))s"
            return (h, s)
        }.sorted { $0.0 < $1.0 }
    }
}
