    private func timeout<T: Sendable>(_ s: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { grp in
            grp.addTask { try await op() }
            grp.addTask {
                try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
                throw ModelError.timeout
            }
            defer { grp.cancelAll() }
            guard let r = try await grp.next() else { throw ModelError.timeout }
            return r
        }
    }

    private func parse(_ raw: String) -> Reply {
        var r = Reply()
        r.raw = raw
        let c = raw.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = c.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            r.answer = c
            return r
        }
        if let m = o["mode"] as? String, !m.isEmpty { r.mode = m }
        if let l = o["letter"] as? String {
            let u = l.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if u.count == 1, Resolve.letters.contains(u) { r.letter = u }
        }
        r.answer = (o["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        r.confidence = o["confidence"] as? Double
        r.reason = (o["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return r
    }
}
