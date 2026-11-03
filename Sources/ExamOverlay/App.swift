import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct Reply {
        var mode = "mcq"
        var letter: String?
        var answer = ""
        var confidence: Double?
        var reason: String?
        var raw = ""
    }

    private var panel: Panel!
    private let state = UIState()
    private let keys = HotKeys()
    private var statusItem: NSStatusItem?
    private var config = Config.load()

    private var boxes: [(String, CGRect)] = []
    private var scale: CGFloat = 2
    private var lastImage: CGImage?
    private var lastText = ""
    private var lastTarget: CGRect?
    private var lastLabels: [(String, CGRect)] = []

    private var task: Task<Void, Never>?
    private var dimTask: Task<Void, Never>?
    private var gen = 0
    private var stream = ""
    private var format = Format.auto
    private var previousApp: NSRunningApplication?
    private var letterMode = false
    private var savedFrame: NSRect?
    private var shiftDown = false
    private var shiftUsed = false

    func applicationDidFinishLaunching(_ n: Notification) {
        Config.seedIfMissing(bundled: Bundle.main.url(forResource: "defaults", withExtension: "json"))
        config = Config.load()
        letterMode = config.letterMode
        state.letterMode = letterMode
        Log.write("=== launch \(Bundle.main.bundlePath) translocated=\(Doctor.translocated) ===")

        buildPanel()
        buildMenu()
        register()
        installMonitors()

        if Doctor.translocated {
            state.text = "Running from a disk image - permissions will not stick.\nRun Install.command, then launch from Applications."
        } else if config.apiKey.isEmpty {
            state.text = "No API key. OV menu > Open config file, set \"apiKey\", then /reload."
        } else if !Doctor.screenGranted || !Doctor.axGranted {
            Doctor.requestBoth()
            state.text = "Grant Screen Recording and Accessibility, then quit and reopen."
        } else {
            state.text = hint
        }
    }

    private var hint: String {
        letterMode ? "8 solve | J fix | right-shift show/hide | ^⌥⌘L normal"
                   : "S solve | P ask | X panic | J fix | K chrome | ^⌥⌘L letter mode"
    }

    private func installMonitors() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard let self, e.keyCode == 60 else { return }
            if e.modifierFlags.contains(.shift) {
                self.shiftDown = true
                self.shiftUsed = false
            } else if self.shiftDown {
                self.shiftDown = false
                if !self.shiftUsed { Task { @MainActor in self.toggleShow() } }
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in self?.shiftUsed = true }
    }

    private func buildPanel() {
        panel = Panel()
        panel.contentView = NSHostingView(rootView: Overlay(
            state: state,
            submit: { [weak self] in self?.submitPrompt() },
            cancel: { [weak self] in self?.closePrompt() }))
        if let v = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: v.maxX - 464, y: v.maxY - 224, width: 440, height: 200), display: false)
        }
        if letterMode {
            if let r = corner(64, 48) { panel.setFrame(r, display: false) }
            panel.ignoresMouseEvents = true
        } else {
            panel.ignoresMouseEvents = config.clickThrough
        }
        panel.orderFrontRegardless()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "OV"
        let m = NSMenu()
        func add(_ t: String, _ s: Selector) { m.addItem(NSMenuItem(title: t, action: s, keyEquivalent: "")) }
        add("Solve", #selector(doSolve))
        add("Solve clipboard", #selector(doClipboard))
        add("Ask…", #selector(doAsk))
        add("Save question", #selector(doSave))
        m.addItem(.separator())
        add("Letter mode", #selector(doLetter))
        add("Cycle format", #selector(doFormat))
        add("Toggle vision", #selector(doVision))
        add("Status / doctor", #selector(doDoctor))
        m.addItem(.separator())
        add("Grant screen recording…", #selector(paneScreen))
        add("Grant accessibility…", #selector(paneAX))
        m.addItem(.separator())
        add("Open captures", #selector(doOpen))
        add("Open config file", #selector(doOpenConfig))
        add("Clear cache", #selector(doClearCache))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = m
        statusItem = item
        statusItem?.isVisible = !(config.hideStatusItem && letterMode)
    }

    @objc private func doSolve() { solve(nil) }
    @objc private func doClipboard() { clipboard() }
    @objc private func doAsk() { openPrompt() }
    @objc private func doSave() { saveOnly() }
    @objc private func doLetter() { setLetter(!letterMode) }
    @objc private func doOpen() { NSWorkspace.shared.open(Archive.dir) }
    @objc private func doOpenConfig() { NSWorkspace.shared.open(Config.path) }
    @objc private func paneScreen() { Doctor.open(.screen) }
    @objc private func paneAX() { Doctor.open(.access) }
    @objc private func doClearCache() { Cache.clear(); flash("cache cleared") }
    @objc private func doVision() { config.attachImage.toggle(); flash(config.attachImage ? "vision ON" : "vision off") }
    @objc private func doFormat() { format = format.next; flash("Format: \(format.rawValue)") }
    @objc private func doDoctor() {
        state.asked = nil
        if letterMode { setLetter(false) }
        flash(Doctor.summary())
    }

    private func flash(_ t: String) {
        state.text = t
        state.dim = false
        panel.orderFrontRegardless()
    }

    private func register() {
        let mod = UInt32(controlKey | optionKey | cmdKey)
        keys.clear()
        if letterMode {
            keys.add(UInt32(kVK_ANSI_8), 0) { [weak self] in
                Task { @MainActor in
                    guard let self, !self.state.promptShown else { return }
                    self.solve(nil)
                }
            }
        } else {
            keys.add(UInt32(kVK_ANSI_S), mod) { [weak self] in Task { @MainActor in self?.solve(nil) } }
        }
        keys.add(UInt32(kVK_ANSI_P), mod) { [weak self] in Task { @MainActor in self?.openPrompt() } }
        keys.add(UInt32(kVK_ANSI_V), mod) { [weak self] in Task { @MainActor in self?.clipboard() } }
        keys.add(UInt32(kVK_ANSI_D), mod) { [weak self] in Task { @MainActor in self?.saveOnly() } }
        keys.add(UInt32(kVK_ANSI_F), mod) { [weak self] in Task { @MainActor in self?.doFormat() } }
        keys.add(UInt32(kVK_ANSI_J), mod) { [weak self] in Task { @MainActor in self?.correct() } }
        keys.add(UInt32(kVK_ANSI_K), mod) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.state.showChrome.toggle()
                self.panel.orderFrontRegardless()
            }
        }
        keys.add(UInt32(kVK_ANSI_L), mod) { [weak self] in
            Task { @MainActor in guard let self else { return }; self.setLetter(!self.letterMode) }
        }
        keys.add(UInt32(kVK_ANSI_X), mod) { [weak self] in Task { @MainActor in self?.panic() } }
        keys.add(UInt32(kVK_ANSI_R), mod) { [weak self] in Task { @MainActor in self?.reveal() } }
        keys.add(UInt32(kVK_ANSI_H), mod) { [weak self] in Task { @MainActor in self?.toggleShow() } }
        keys.add(UInt32(kVK_ANSI_O), mod) { [weak self] in Task { @MainActor in self?.doDoctor() } }
    }

    private func corner(_ w: CGFloat, _ h: CGFloat) -> NSRect? {
        guard let v = NSScreen.main?.visibleFrame else { return nil }
        return NSRect(x: v.maxX - w - 14, y: v.minY + 14, width: w, height: h)
    }

    private func setLetter(_ on: Bool) {
        guard on != letterMode else { return }
        letterMode = on
        state.letterMode = on
        state.full = ""
        state.text = ""
        state.dim = false
        if on {
            savedFrame = panel.frame
            if let r = corner(64, 48) { panel.setFrame(r, display: true) }
            panel.ignoresMouseEvents = true
            if config.hideStatusItem { statusItem?.isVisible = false }
        } else {
            if let r = savedFrame { panel.setFrame(r, display: true) }
            panel.ignoresMouseEvents = config.clickThrough
            statusItem?.isVisible = true
            state.text = hint
        }
        panel.orderFrontRegardless()
        register()
    }

    private func toggleShow() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func panic() {
        task?.cancel()
        dimTask?.cancel()
        state.busy = false
        state.text = ""
        state.full = ""
        state.asked = nil
        state.promptShown = false
        state.dim = false
        panel.orderOut(nil)
    }

    private func reveal() {
        if !state.full.isEmpty, state.text != state.full {
            state.text = state.full
            if letterMode, let r = corner(380, 180) { panel.setFrame(r, display: true) }
        } else if letterMode, let r = corner(64, 48) {
            state.text = ""
            panel.setFrame(r, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func openPrompt() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if letterMode, let r = corner(440, 200) {
            savedFrame = panel.frame
            panel.setFrame(r, display: true)
        }
        state.promptShown = true
        panel.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func submitPrompt() {
        let raw = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        state.promptShown = false
        state.prompt = ""
        endPrompt()
        guard !raw.isEmpty else { solve(nil); return }
        if state.history.first != raw {
            state.history.insert(raw, at: 0)
            if state.history.count > 25 { state.history.removeLast() }
        }
        if raw.hasPrefix("/") { runCommand(raw); return }
        ask(raw)
    }

    private func runCommand(_ raw: String) {
        let cmd = raw.dropFirst().split(separator: " ", maxSplits: 1).first.map { String($0).lowercased() } ?? ""
        switch cmd {
        case "cache": doClearCache()
        case "clear": state.text = ""; state.full = ""; panel.orderFrontRegardless()
        case "format": doFormat()
        case "letter": setLetter(!letterMode)
        case "vision": doVision()
        case "doctor": doDoctor()
        case "config": NSWorkspace.shared.open(Config.path)
        case "reload":
            config = Config.load()
            flash("config reloaded")
        case "save": saveOnly()
        case "quit": NSApp.terminate(nil)
        default:
            if let q = Shortcuts.expand(raw) { ask(q); return }
            flash("unknown /\(cmd) - /def /conj /translate /explain /grammar /math /vision /reload")
        }
    }

    private func closePrompt() {
        state.promptShown = false
        state.prompt = ""
        endPrompt()
    }

    private func endPrompt() {
        if letterMode {
            if let r = savedFrame ?? corner(64, 48) { panel.setFrame(r, display: true) }
            panel.ignoresMouseEvents = true
        }
        _ = previousApp?.activate(options: [])
        previousApp = nil
    }

    private func solve(_ clip: String?) { run(clipboard: clip, ask: nil) }

    private func clipboard() {
        let t = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard t.count >= 5 else { flash("clipboard empty"); return }
        run(clipboard: t, ask: nil)
    }

    private func ask(_ q: String) { run(clipboard: nil, ask: q) }

    private func saveOnly() {
        guard !state.busy else { return }
        gen += 1
        let g = gen
        state.busy = true
        task = Task { @MainActor in
            guard let r = await self.grab(g) else { return }
            let f = Archive.save(question: r.text, answer: self.state.full, image: r.image)
            self.set(g, f.map { "saved \($0.lastPathComponent)" } ?? "save failed")
        }
    }

    private func run(clipboard: String?, ask: String?) {
        guard !state.busy else { Log.write("busy, ignored"); return }
        gen += 1
        let g = gen
        task?.cancel()
        state.busy = true
        state.asked = ask
        state.cached = false
        state.dim = false
        state.text = "…"
        panel.orderFrontRegardless()
        task = Task { @MainActor in
            if let q = ask { await self.doAsk(g, q) } else { await self.doSolve(g, clipboard) }
        }
    }

    private typealias Grab = (image: CGImage, scale: CGFloat, text: String, boxes: [(String, CGRect)])

    private func grab(_ g: Int) async -> Grab? {
        guard Doctor.screenGranted else {
            Doctor.requestScreen()
            set(g, "Screen Recording missing - OV menu > Grant screen recording…")
            return nil
        }
        guard let shot = await Capture.screen() else { set(g, "capture failed"); return nil }
        let (ocr, bx) = Capture.text(in: shot.image, languages: config.ocrLanguages)
        boxes = bx
        scale = shot.scale
        lastImage = shot.image
        let text = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        lastText = text
        Log.write("grab \(shot.image.width)x\(shot.image.height) boxes=\(bx.count) chars=\(text.count)")
        try? text.write(to: URL(fileURLWithPath: "/tmp/examoverlay-ocr.txt"), atomically: true, encoding: .utf8)
        guard text.count >= 5 else { set(g, "no text (\(bx.count) boxes)"); return nil }
        return (shot.image, shot.scale, text, bx)
    }

    private func doSolve(_ g: Int, _ clip: String?) async {
        let cfg = config
        let text: String
        let image: CGImage?
        if let c = clip {
            text = c
            image = lastImage
        } else {
            guard let r = await grab(g) else { return }
            text = r.text
            image = r.image
        }

        let labels = Resolve.labels(boxes)
        lastLabels = labels
        let hint = format == .auto ? "" : "\n\nFormat hint: \(format.rawValue)"
        let prompt = text + hint
        let wantImage = cfg.attachImage || text.count < 200
        let vision = wantImage ? image.map { Capture.downscale($0, maxWidth: 1100) } : nil
        Log.write("solve labels=\(labels.map { $0.0 }.joined()) image=\(vision != nil) chars=\(text.count)")

        let key = Cache.key(prompt, cfg.model)
        if cfg.useCache, let hit = Cache.get(key) {
            await present(parse(hit), labels, g, cfg, cached: true)
            return
        }

        var replies: [Reply] = []
        let n = max(1, cfg.consensusSamples)
        if n == 1 {
            do {
                let raw = try await timeout(40) { try await Model.solve(prompt, image: vision, cfg) }
                guard g == gen else { return }
                Log.write("raw \(raw.prefix(300))")
                replies = [parse(raw)]
            } catch {
                if Task.isCancelled { return }
                Log.write("model error: \(error)")
                set(g, "Error: \(error)")
                return
            }
        } else {
            var tasks: [Task<Reply?, Never>] = []
            for _ in 0..<n {
                tasks.append(Task {
                    do {
                        let raw = try await self.timeout(40) { try await Model.solve(prompt, image: vision, cfg) }
                        return self.parse(raw)
                    } catch { return nil }
                })
            }
            for t in tasks { if let r = await t.value { replies.append(r) } }
            guard g == gen else { return }
        }

        let valid = replies.filter { !$0.answer.isEmpty || $0.letter != nil }
        guard var chosen = valid.first else { set(g, "Error: empty response"); return }
        if valid.count > 1 {
            var tally: [String: Int] = [:]
            for r in valid {
                if let l = r.letter, labels.isEmpty || (Resolve.index(l) ?? 99) < labels.count {
                    tally[l, default: 0] += 1
                }
            }
            if let best = tally.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
               let r = valid.first(where: { $0.letter == best.key }) {
                chosen = r
                Log.write("vote \(best.value)/\(valid.count) -> \(best.key)")
            }
        }
        if cfg.useCache { Cache.put(key, chosen.raw) }
        await present(chosen, labels, g, cfg, cached: false)
    }

    private func doAsk(_ g: Int, _ q: String) async {
        let cfg = config
        let noScreen = q.hasPrefix("!")
        let question = noScreen ? String(q.dropFirst()).trimmingCharacters(in: .whitespaces) : q
        var c0 = ""
        var i0: CGImage?
        if !noScreen {
            guard let r = await grab(g) else { return }
            c0 = r.text
            i0 = cfg.attachImage ? Capture.downscale(r.image, maxWidth: 1100) : nil
        }
        let ctx = c0
        let image = i0
        stream = ""
        if cfg.streamAsk {
            do {
                let raw = try await timeout(40) {
                    try await Model.askStream(question, ctx, image, cfg) { piece in
                        Task { @MainActor in
                            guard g == self.gen else { return }
                            self.stream += piece
                            self.state.text = self.stream
                        }
                    }
                }
                guard g == gen else { return }
                state.full = raw
                set(g, raw)
                return
            } catch {
                if Task.isCancelled { return }
            }
        }
        do {
            let raw = try await timeout(40) { try await Model.ask(question, ctx, image, cfg) }
            guard g == gen else { return }
            state.full = raw
            set(g, raw)
        } catch {
            if Task.isCancelled { return }
            set(g, "Error: \(error)")
        }
    }

    private func present(_ r: Reply, _ labels: [(String, CGRect)], _ g: Int, _ cfg: Config, cached: Bool) async {
        state.cached = cached
        if let img = lastImage, letterMode { sampleContrast(img) }
        let hi = max(cfg.revealMin, cfg.revealMax)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: cfg.revealMin...hi) * 1_000_000_000))
        guard g == gen else { return }

        var letter = r.letter
        if let l = letter, labels.count >= 2, let i = Resolve.index(l), i >= labels.count {
            letter = Resolve.letters[labels.count - 1]
        }
        let target = r.mode == "mcq" ? Resolve.target(answer: r.answer, letter: letter, boxes: boxes) : nil
        if letter == nil, let t = target { letter = Resolve.letter(for: t.box, labels: labels) }

        var full = r.answer
        if let reason = r.reason, !reason.isEmpty { full += "\n\(reason)" }
        if let c = r.confidence { full += "  [\(Int(c * 100))%]" }
        state.full = full
        Log.write("present mode=\(r.mode) letter=\(letter ?? "-") answer=\(r.answer.prefix(60)) target=\(target?.tier ?? "none")")

        if letterMode {
            if r.mode == "mcq" { set(g, letter ?? "?") }
            else { set(g, String(r.answer.prefix(18))) }
        } else {
            set(g, full.isEmpty ? "(empty) \(r.raw.prefix(120))" : full)
        }

        AnswerLog.record(question: lastText, letter: letter ?? "-", answer: r.answer,
                         confidence: r.confidence ?? 0, tier: target?.tier ?? "none")

        guard r.mode == "mcq", let t = target else {
            if r.mode == "mcq" { Log.write("click: UNRESOLVED") }
            return
        }
        lastTarget = t.box
        Log.write("click: \(t.tier) \(t.text.prefix(40))")
        Capture.click(pixel: jitter(t.box), scale: scale)

        if cfg.autoSave { Archive.save(question: lastText, answer: full, image: lastImage) }
    }

    private func sampleContrast(_ img: CGImage) {
        guard let s = NSScreen.main else { return }
        let o = Capture.origin
        let r = panel.frame
        let top = s.frame.height - r.maxY
        let px = CGRect(x: (r.minX - o.x) * scale, y: (top - o.y) * scale,
                        width: r.width * scale, height: r.height * scale)
        state.onDark = Capture.luminance(img, in: px) < 118
    }

    private func jitter(_ b: CGRect) -> CGPoint {
        CGPoint(x: b.minX + CGFloat.random(in: 0.3...0.7) * b.width,
                y: b.minY + CGFloat.random(in: 0.3...0.7) * b.height)
    }

    private func correct() {
        guard let b = lastTarget else { flash("nothing to shift"); return }
        let rows = lastLabels.isEmpty ? Resolve.rows(boxes) : lastLabels.map { $0.1 }
        let next = rows.first { $0.minY > b.maxY - 2 } ?? b.offsetBy(dx: 0, dy: max(b.height, 14) * 1.3)
        lastTarget = next
        Capture.click(pixel: jitter(next), scale: scale)
        Log.write("click: shifted")
    }

    private func set(_ g: Int, _ t: String) {
        guard g == gen else { return }
        state.text = t
        state.busy = false
        state.dim = false
        dimTask?.cancel()
        dimTask = Task { [g] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, g == self.gen else { return }
            self.state.dim = true
        }
    }

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
