import CoreGraphics
import Foundation

enum ModelError: Error, CustomStringConvertible {
    case timeout, http(Int, String), empty
    var description: String {
        switch self {
        case .timeout: return "timed out"
        case .http(let c, let b): return "HTTP \(c): \(b.prefix(600))"
        case .empty: return "empty response"
        }
    }
}

enum Model {
    static let solveSystem = """
    You answer exam questions from OCR text of a screen. The text may include browser chrome, a stimulus passage, the question, and answer choices, which may or may not be lettered.
    Return JSON only, no prose, no code fences:
    {"mode":"mcq","letter":"B","answer":"exact choice text","confidence":0.9,"reason":"one sentence"}
    Rules:
    - mode is "mcq" when answer choices exist, "short" for written responses, "fill" for blanks.
    - For mcq, "answer" must copy the chosen choice's text exactly as it appears in the input, so it can be located on screen.
    - "letter" is the choice's label if labels are present, otherwise its position among the choices (A = first). Never invent a label that does not exist. Use "" when not mcq.
    - confidence is 0 to 1.
    """

    static let askSystem = "You are a concise exam helper. Answer in the language asked. No preamble."

    static func solve(_ text: String, image: CGImage?, _ c: Config, history: String = "") async throws -> String {
        let u = content(history + text, image)
        let skipPrimary = !(await Health.shared.usable(c.endpoint))
        var last: Error?
        for attempt in 0..<2 where !skipPrimary {
            await Budget.shared.reserve(text.count / 4 + history.count / 4 + (image == nil ? 0 : 1100) + c.maxTokens)
            do {
                let r = try await once(solveSystem, u, c, json: true)
                await Health.shared.mark(c.endpoint, ok: true)
                return r
            }
            catch {
                last = error
                if !retryable(error) { await Health.shared.mark(c.endpoint, ok: false) }
                guard retryable(error), attempt < 2 else { break }
                let wait = retryAfter(error)
                Log.write("throttled, waiting \(Int(wait))s")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        guard let fb = fallback(c) else { throw last ?? ModelError.empty }
        Log.write("primary failed (\(last.map { "\($0)" } ?? "?")), trying fallback \(fb.model)")
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            let r = try await once(solveSystem, u, fb, json: true)
            await Health.shared.mark(fb.endpoint, ok: true)
            return stripJSON(r)
        } catch {
            await Health.shared.mark(fb.endpoint, ok: false)
            throw error
        }
    }

    private static func retryable(_ e: Error) -> Bool {
        if case ModelError.http(let c, _) = e { return c == 429 || c == 503 }
        return false
    }

    private static func retryAfter(_ e: Error) -> Double {
        if case ModelError.http(_, let b) = e,
           let r = b.range(of: "try again in") {
            let tail = b[r.upperBound...].prefix(12)
            let digits = tail.prefix { $0.isNumber || $0 == "." }
            if let v = Double(digits) { return min(max(v + 0.5, 1), 20) }
        }
        return 9
    }

    private static func fallback(_ c: Config) -> Config? {
        guard let e = c.fallbackEndpoint, !c.fallbackModel.isEmpty, !c.fallbackApiKey.isEmpty else { return nil }
        var f = c
        f.endpoint = e
        f.model = c.fallbackModel
        f.apiKey = c.fallbackApiKey
        f.consensusSamples = 1
        f.isFallback = true
        return f
    }

    static func ask(_ q: String, _ ctx: String, _ image: CGImage?, _ c: Config) async throws -> String {
        let u = content(askText(q, ctx), image)
        await Budget.shared.reserve(q.count / 4 + ctx.count / 4 + (image == nil ? 0 : 1600) + c.maxTokens)
        do {
            return try await once(askSystem, u, c, json: false)
        } catch {
            guard let fb = fallback(c) else { throw error }
            Log.write("ask primary failed (\(error)), trying fallback \(fb.model)")
            try? await Task.sleep(nanoseconds: 300_000_000)
            return try await once(askSystem, u, fb, json: false)
        }
    }

    static func askStream(_ q: String, _ ctx: String, _ image: CGImage?, _ c: Config,
                          _ onPiece: @escaping (String) -> Void) async throws -> String {
        let u = content(askText(q, ctx), image)
        await Budget.shared.reserve(q.count / 4 + ctx.count / 4 + (image == nil ? 0 : 1600) + c.maxTokens)
        do {
            return try await stream(askSystem, u, c, onPiece)
        } catch {
            guard let fb = fallback(c) else { throw error }
            Log.write("ask stream failed (\(error)), trying fallback \(fb.model)")
            try? await Task.sleep(nanoseconds: 300_000_000)
            let out = try await once(askSystem, u, fb, json: false)
            onPiece(out)
            return out
        }
    }

    private static func stream(_ sys: String, _ u: Any, _ c: Config,
                               _ onPiece: @escaping (String) -> Void) async throws -> String {
        var req = try build(sys, u, c, json: false)
        var body = (try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
        body["stream"] = true
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelError.empty
        }
        var out = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let ch = o["choices"] as? [[String: Any]],
                  let delta = ch.first?["delta"] as? [String: Any],
                  let piece = delta["content"] as? String else { continue }
            out += piece
            onPiece(piece)
        }
        guard !out.isEmpty else { throw ModelError.empty }
        return out
    }

    struct BatchItem {
        let n: Int
        let letter: String
        let answer: String
    }

    static func batch(_ text: String, image: CGImage?, _ c: Config) async throws -> [BatchItem] {
        let sys = """
        Find every numbered question visible. For each, pick the best option.
        Return JSON only: {"items":[{"n":1,"letter":"B","answer":"exact option text"}]}
        """
        let u = content(text, image)
        await Budget.shared.reserve(text.count / 4 + (image == nil ? 0 : 1600) + 500)
        let raw = stripJSON(try await once(sys, u, c, json: true))
        guard let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = o["items"] as? [[String: Any]] else { return [] }
        return arr.compactMap { i in
            guard let n = i["n"] as? Int, let l = i["letter"] as? String else { return nil }
            return BatchItem(n: n, letter: l.uppercased(), answer: i["answer"] as? String ?? "")
        }.sorted { $0.n < $1.n }
    }

    static func eliminate(_ text: String, image: CGImage?, _ c: Config) async throws -> [String] {
        let sys = "Return JSON only: {\"eliminate\":[\"A\",\"C\"]}. Choose the two least likely options."
        let u = content(text, image)
        await Budget.shared.reserve(text.count / 4 + (image == nil ? 0 : 1600) + 200)
        let raw = stripJSON(try await once(sys, u, c, json: true))
        guard let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = o["eliminate"] as? [String] else { return [] }
        return Array(arr.map { $0.uppercased() }.prefix(3))
    }

    private static func askText(_ q: String, _ ctx: String) -> String {
        ctx.isEmpty ? q : "Screen text:\n\(ctx)\n\nQuestion: \(q)"
    }

    private static func content(_ text: String, _ image: CGImage?) -> Any {
        guard let image, let png = Capture.png(image) else { return text }
        let note = "\n\nA screenshot is attached. Read any map, chart, cartoon or document in it; the OCR text may be incomplete."
        return [["type": "text", "text": text + note],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(png.base64EncodedString())"]]]
    }

    private static func stripJSON(_ s: String) -> String {
        guard let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b else { return s }
        return String(s[a...b])
    }

    private static func once(_ sys: String, _ u: Any, _ c: Config, json: Bool) async throws -> String {
        let req = try build(sys, u, c, json: json)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ModelError.empty }
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else { throw ModelError.http(http.statusCode, bodyText) }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelError.http(http.statusCode, bodyText)
        }
        if let e = (o["error"] as? [String: Any])?["message"] as? String { throw ModelError.http(http.statusCode, e) }
        guard let ch = o["choices"] as? [[String: Any]],
              let msg = ch.first?["message"] as? [String: Any],
              let s = msg["content"] as? String, !s.isEmpty else {
            throw ModelError.http(http.statusCode, "empty content: \(bodyText.prefix(200))")
        }
        return s
    }

    private static func build(_ sys: String, _ u: Any, _ c: Config, json: Bool) throws -> URLRequest {
        var req = URLRequest(url: c.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = c.isFallback ? 14 : 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(c.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")
        var body: [String: Any] = [
            "model": c.model,
            "temperature": c.consensusSamples > 1 ? max(c.temperature, 0.5) : c.temperature,
            "max_tokens": c.maxTokens,
            "messages": [["role": "system", "content": sys], ["role": "user", "content": u]]
        ]
        if json {
            body["response_format"] = ["type": "json_object"]
        }
        if c.endpoint.host?.contains("deepseek") == true {
            if json {
                body["thinking"] = ["type": "disabled"]
                body["effort"] = "low"
            }
        } else {
            body["reasoning_effort"] = "none"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}
