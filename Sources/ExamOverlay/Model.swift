import CoreGraphics
import Foundation

enum ModelError: Error, CustomStringConvertible {
    case timeout, http(Int, String), empty
    var description: String {
        switch self {
        case .timeout: return "timed out"
        case .http(let c, let b): return "HTTP \(c): \(b.prefix(160))"
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

    static func solve(_ text: String, image: CGImage?, _ c: Config) async throws -> String {
        try await once(solveSystem, content(text, image), c, json: true)
    }

    static func ask(_ q: String, _ ctx: String, _ image: CGImage?, _ c: Config) async throws -> String {
        try await once(askSystem, content(askText(q, ctx), image), c, json: false)
    }

    static func askStream(_ q: String, _ ctx: String, _ image: CGImage?, _ c: Config,
                          _ onPiece: @escaping (String) -> Void) async throws -> String {
        var req = try build(askSystem, content(askText(q, ctx), image), c, json: false)
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
        return out
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
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(c.apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": c.model,
            "temperature": c.consensusSamples > 1 ? max(c.temperature, 0.5) : c.temperature,
            "max_tokens": c.maxTokens,
            "messages": [["role": "system", "content": sys], ["role": "user", "content": u]]
        ]
        if json { body["response_format"] = ["type": "json_object"] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}
