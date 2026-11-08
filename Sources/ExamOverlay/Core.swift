import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum Log {
    private static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".examoverlay.log")
    private static let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func write(_ s: String) {
        let line = "[\(fmt.string(from: Date()))] \(s)\n"
        guard let d = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if let size = try? fm.attributesOfItem(atPath: path.path)[.size] as? Int, size > 400_000 {
            try? fm.removeItem(at: path)
        }
        if let h = try? FileHandle(forWritingTo: path) {
            h.seekToEndOfFile()
            h.write(d)
            try? h.close()
        } else {
            try? d.write(to: path)
        }
    }
}

enum Format: String {
    case auto, mcq, fill, short
    var next: Format {
        switch self {
        case .auto: return .mcq
        case .mcq: return .fill
        case .fill: return .short
        case .short: return .auto
        }
    }
}

enum Display: String {
case ghost, compact, full
var next: Display {
switch self {
case .ghost: return .compact
case .compact: return .full
case .full: return .ghost
}
}
var size: CGSize {
switch self {
case .ghost: return CGSize(width: 56, height: 44)
case .compact: return CGSize(width: 320, height: 92)
case .full: return CGSize(width: 440, height: 220)
}
}
}

struct Config {
    var endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    var model = "deepseek-flash"
    var apiKey = ""
    var fallbackEndpoint: URL?
    var fallbackModel = ""
    var fallbackApiKey = ""
    var isFallback = false
    var maxTokens = 1200
    var attachImage = true
    var useCache = true
    var streamAsk = true
    var consensusSamples = 1
    var temperature = 0.1
    var autoSave = false
    var ocrLanguages = ["en-US", "es-ES"]
    var revealMin = 0.6
    var revealMax = 1.2
    var clickJitter = 0.15...0.40
    var display = Display.ghost
 var confidenceFloor = 0.55
 var showHints = true
 var onboarded = false
    var autoMaxSteps = 40
    var axText = true
    var autoWrongChance = 0.25
    var autoDwellScale = 1.0
    var autoStopConfidence = 0.4
    var clickThrough = true
    var hideStatusItem = true

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".examoverlay.json")

    static func seedIfMissing(bundled: URL?) {
        guard !FileManager.default.fileExists(atPath: path.path) else { return }
        if let b = bundled, let d = try? Data(contentsOf: b) { try? d.write(to: path) }
    }

    static func load() -> Config {
        var c = Config()
        guard let d = try? Data(contentsOf: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return c }
        if let v = o["endpoint"] as? String, let u = URL(string: v) { c.endpoint = u }
        if let v = o["model"] as? String { c.model = v }
        if let v = o["apiKey"] as? String { c.apiKey = v }
        if let v = o["fallbackEndpoint"] as? String { c.fallbackEndpoint = URL(string: v) }
        if let v = o["fallbackModel"] as? String { c.fallbackModel = v }
        if let v = o["fallbackApiKey"] as? String { c.fallbackApiKey = v }
        if let v = o["maxTokens"] as? Int { c.maxTokens = v }
        if let v = o["attachImage"] as? Bool { c.attachImage = v }
        if let v = o["useCache"] as? Bool { c.useCache = v }
        if let v = o["streamAsk"] as? Bool { c.streamAsk = v }
        if let v = o["consensusSamples"] as? Int { c.consensusSamples = max(1, min(5, v)) }
        if let v = o["temperature"] as? Double { c.temperature = v }
        if let v = o["autoSave"] as? Bool { c.autoSave = v }
        if let v = o["ocrLanguages"] as? [String] { c.ocrLanguages = v }
        if let v = o["revealMin"] as? Double { c.revealMin = v }
        if let v = o["revealMax"] as? Double { c.revealMax = v }
        if let v = o["display"] as? String, let d = Display(rawValue: v) { c.display = d }
else if let v = o["letterMode"] as? Bool { c.display = v ? .ghost : .full }
if let v = o["confidenceFloor"] as? Double { c.confidenceFloor = v }
if let v = o["showHints"] as? Bool { c.showHints = v }
if let v = o["onboarded"] as? Bool { c.onboarded = v }
        if let v = o["autoMaxSteps"] as? Int { c.autoMaxSteps = v }
        if let v = o["axText"] as? Bool { c.axText = v }
        if let v = o["autoWrongChance"] as? Double { c.autoWrongChance = v }
        if let v = o["autoDwellScale"] as? Double { c.autoDwellScale = v }
        if let v = o["autoStopConfidence"] as? Double { c.autoStopConfidence = v }
        if let v = o["clickThrough"] as? Bool { c.clickThrough = v }
        if let v = o["hideStatusItem"] as? Bool { c.hideStatusItem = v }
        return c
    }
}

enum Doctor {
    enum Pane { case screen, access }

    static var screenGranted: Bool { CGPreflightScreenCaptureAccess() }
    static var axGranted: Bool { AXIsProcessTrusted() }
    static var translocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    static func requestScreen() { CGRequestScreenCaptureAccess() }

    static func requestBoth() {
        if !screenGranted { requestScreen() }
        if !axGranted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    static func open(_ p: Pane) {
        let s = p == .screen
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    static func summary() -> String {
        """
        bundle: \(Bundle.main.bundlePath)
        translocated: \(translocated)
        screen recording: \(screenGranted ? "yes" : "NO")
        accessibility: \(axGranted ? "yes" : "NO")
        log: ~/.examoverlay.log
        """
    }
}

final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    static weak var shared: HotKeys?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeys.shared?.actions[id.id]?()
            return noErr
        }, 1, &spec, nil, &handler)
    }

    func add(_ key: UInt32, _ mods: UInt32, _ action: @escaping () -> Void) {
        HotKeys.shared = self
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4F56_4552), id: id)
        RegisterEventHotKey(key, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if let ref { refs.append(ref) }
    }

    func clear() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }
}

enum Shortcuts {
    static func expand(_ raw: String) -> String? {
        let parts = raw.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first?.lowercased(), parts.count > 1 else { return nil }
        let arg = parts[1]
        switch cmd {
        case "def": return "Define \"\(arg)\" in one sentence. Spanish, then English."
        case "conj": return "Conjugate \"\(arg)\" fully: present, preterite, imperfect, subjunctive. Table only."
        case "translate": return "Translate to English: \(arg)"
        case "explain": return "Explain the grammar of: \(arg)"
        case "grammar": return "Correct this Spanish, then list each error briefly: \(arg)"
        case "math": return "Solve step by step: \(arg)"
        default: return nil
        }
    }
}

enum Cache {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".examoverlay-cache.json")

    private static func read() -> [String: String] {
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String]
        else { return [:] }
        return o
    }

    static func key(_ text: String, _ model: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in Array("\(model)|\(text)".utf8) { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }

    static func get(_ k: String) -> String? { read()[k] }

    static func put(_ k: String, _ v: String) {
        var o = read()
        o[k] = v
        if o.count > 500 { o = [:] }
        if let d = try? JSONSerialization.data(withJSONObject: o) { try? d.write(to: url) }
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}

enum Archive {
    static var dir: URL {
        let u = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ExamOverlay/captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    static func save(question: String, answer: String, image: CGImage?) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = dir.appendingPathComponent(stamp, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? question.write(to: folder.appendingPathComponent("question.txt"), atomically: true, encoding: .utf8)
        try? answer.write(to: folder.appendingPathComponent("answer.txt"), atomically: true, encoding: .utf8)
        if let image, let png = Capture.png(image, maxWidth: 2400) {
            try? png.write(to: folder.appendingPathComponent("screen.png"))
        }
        return folder
    }
}

enum AnswerLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExamOverlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("answers.jsonl")
    }()

    static func entries(since: Date) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        return text.split(separator: "\n").compactMap { line in
            guard let d = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let t = o["t"] as? String, let date = iso.date(from: t), date > since
            else { return nil }
            return o
        }
    }

    static func record(question: String, letter: String, answer: String, confidence: Double, tier: String) {
        let obj: [String: Any] = [
            "t": ISO8601DateFormatter().string(from: Date()),
            "q": String(question.prefix(300)),
            "letter": letter,
            "answer": String(answer.prefix(200)),
            "confidence": confidence,
            "tier": tier
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: d, encoding: .utf8) else { return }
        line += "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
