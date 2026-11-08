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
    private var batchRows: [Model.BatchItem] = []
    private var batchIndex = -1
    private var pinnedText = ""
    private var sessionStart = Date()
    private var qStart = Date()
    private var clock: Timer?
    private var prevText = ""
    private var lastTarget: CGRect?
    private var targetStack: [CGRect] = []
    private var wizardShown = false
    private var lastLabels: [(String, CGRect)] = []

    private var task: Task<Void, Never>?
    private var dimTask: Task<Void, Never>?
    private var gen = 0
    private var stream = ""
    private var format = Format.auto
    private var previousApp: NSRunningApplication?
    private var display = Display.ghost
    private var savedFrame: NSRect?
    private var shiftDown = false
    private var shiftUsed = false

    func applicationDidFinishLaunching(_ n: Notification) {
        Config.seedIfMissing(bundled: Bundle.main.url(forResource: "defaults", withExtension: "json"))
        config = Config.load()
        display = config.display
        state.display = display
        Log.write("=== launch \(Bundle.main.bundlePath) translocated=\(Doctor.translocated) ===")
        startObservers()
        startClock()
        if !config.onboarded, !wizardShown {
            wizardShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                WizardWindow.show { self.config.onboarded = true }
            }
        }

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
        switch display {
        case .ghost: return "8 solve · J next · ⇧ tap hide · ^⌥⌘L denser"
        case .compact: return "S solve · J next · ⌘Z undo · ^⌥⌘L fuller"
        case .full: return "S solve · P ask · ⌘C copy · ⌘Z undo · ^⌥⌘L ghost"
        }
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
        if display == .ghost {
            if let r = corner(64, 48) { panel.setFrame(r, display: false) }
            panel.ignoresMouseEvents = true
        } else {
            panel.ignoresMouseEvents = config.clickThrough
        }
        panel.orderFrontRegardless()
    }

    private func startObservers() {
        NotificationCenter.default.addObserver(
            forName: .examOverlayConfigChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadConfig() }
        }
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
        add("Cycle density", #selector(doCycle))
        add("Preferences…", #selector(doPrefs))
        add("Setup…", #selector(doWizard))
        add("Review session", #selector(doReview))
        add("Scan whole page", #selector(doBatch))
        add("Eliminate two", #selector(doEliminate))
        add("Explain answer", #selector(doExplain))
        add("Provider health", #selector(doHealth))
        m.addItem(.separator())
        add("Check for updates", #selector(doUpdate))
        add("Build study report", #selector(doReport))
        add("About ExamOverlay", #selector(doAbout))
        add("Export log", #selector(doLog))
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
        statusItem?.isVisible = !(config.hideStatusItem && display == .ghost)
    }

    @objc private func doSolve() { solve(nil) }
    @objc private func doClipboard() { clipboard() }
    @objc private func doAsk() { openPrompt() }
    @objc private func doSave() { saveOnly() }
        @objc private func doCycle() { setDisplay(display.next) }
    @objc private func doPrefs() { PrefsWindow.show() }
    @objc private func doWizard() { WizardWindow.show { } }
    @objc private func doUndo() { undo() }
        private func eliminate() {
        guard !state.busy else { return }
        gen += 1
        let g = gen
        let cfg = config
        let text = lastText
        task = Task { @MainActor in
            state.busy = true
            do {
                let l = try await Model.eliminate(text, image: lastImage, cfg)
                guard g == gen else { return }
                state.eliminated = l
                set(g, l.isEmpty ? "no elimination" : "✗ " + l.joined(separator: "  "))
            } catch {
                if Task.isCancelled { return }
                set(g, describe(error))
            }
        }
    }

    private func explain() {
        guard !state.busy, !state.full.isEmpty else { return }
        gen += 1
        let g = gen
        let cfg = config
        let text = lastText
        let pick = state.letter
        task = Task { @MainActor in
            state.busy = true
            do {
                let r = try await Model.ask("In two sentences, why is \(pick) correct here?", text, lastImage, cfg)
                guard g == gen else { return }
                state.full = r
                set(g, r)
            } catch {
                if Task.isCancelled { return }
                set(g, describe(error))
            }
        }
    }

    private func batchMove(_ d: Int) {
        guard !batchRows.isEmpty else { return }
        batchIndex = min(batchRows.count - 1, max(0, batchIndex + d))
        state.text = batchRows.enumerated().map { i, r in
            (i == batchIndex ? "▶ " : "  ") + "\(r.letter). \(r.answer.prefix(38))"
        }.joined(separator: "\n")
        panel.orderFrontRegardless()
    }

    private func batchClick() {
        guard batchIndex >= 0, batchIndex < batchRows.count else {
            flash("nothing selected"); return
        }
        let r = batchRows[batchIndex]
        guard let t = Resolve.target(answer: r.answer, letter: r.letter, boxes: boxes) else {
            flash("no match"); return
        }
        if let prev = lastTarget { targetStack.append(prev) }
        lastTarget = t.box
        Capture.click(pixel: jitter(t.box), scale: scale)
        Log.write("click: batch \(r.letter)")
    }

    private func batch() {
        guard !state.busy else { return }
        gen += 1
        let g = gen
        let cfg = config
        let text = lastText
        task = Task { @MainActor in
            state.busy = true
            do {
                let items = try await Model.batch(text, image: lastImage, cfg)
                guard g == gen else { return }
                batchRows = items
                batchIndex = -1
                if items.isEmpty { set(g, "no questions found"); return }
                let head = items.prefix(4)
                    .map { "\($0.letter). \($0.answer.prefix(40))" }
                    .joined(separator: "\n")
                set(g, "\(items.count) found\n" + head)
            } catch {
                if Task.isCancelled { return }
                set(g, describe(error))
            }
        }
    }

    @objc private func doReview() { ReviewWindow.show() }

    @objc private func doBatch() { batch() }
    @objc private func doEliminate() { eliminate() }
    @objc private func doExplain() { explain() }
    @objc private func doUpdate() { Update.check(quiet: false) }
    @objc private func doReport() { StudyReport.build() }
    @objc private func doAbout() {
        let al = NSAlert()
        al.messageText = "ExamOverlay \(Update.current)"
        al.informativeText = "Screen capture, OCR, and one key."
        al.runModal()
    }

    @objc private func doLog() {
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".examoverlay.log")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "examoverlay.log"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        try? FileManager.default.removeItem(at: u)
        try? FileManager.default.copyItem(at: p, to: u)
    }

    @objc private func doHealth() {
        Task { @MainActor in
            let rows = await Health.shared.report()
            let body = rows.isEmpty ? "No failures recorded."
                : rows.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            let al = NSAlert()
            al.messageText = "Provider health"
            al.informativeText = body
            al.runModal()
        }
    }
    @objc private func doCopy() { copyAnswer() }
    @objc private func doOpen() { NSWorkspace.shared.open(Archive.dir) }
    @objc private func doOpenConfig() { NSWorkspace.shared.open(Config.path) }
    @objc private func paneScreen() { Doctor.open(.screen) }
    @objc private func paneAX() { Doctor.open(.access) }
    @objc private func doClearCache() { Cache.clear(); Task { await history.clear() }; flash("cache + context cleared") }
    @objc private func doVision() { config.attachImage.toggle(); flash(config.attachImage ? "vision ON" : "vision off") }
    @objc private func doFormat() { format = format.next; flash("Format: \(format.rawValue)") }
    @objc private func doDoctor() {
        state.asked = nil
        if display == .ghost { setDisplay(.full) }
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
        keys.add(UInt32(kVK_ANSI_8), 0) { [weak self] in
            Task { @MainActor in
                guard let self, !self.state.promptShown else { return }
                self.solve(nil)
            }
        }
        keys.add(UInt32(kVK_ANSI_S), mod) { [weak self] in Task { @MainActor in self?.solve(nil) } }
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
            Task { @MainActor in guard let self else { return }; self.setDisplay(self.display.next) }
        }
        keys.add(UInt32(kVK_ANSI_Z), mod) { [weak self] in
            Task { @MainActor in self?.undo() }
        }
        keys.add(UInt32(kVK_ANSI_C), mod) { [weak self] in
            Task { @MainActor in self?.copyAnswer() }
        }
        keys.add(UInt32(kVK_ANSI_Comma), mod) { [weak self] in
            Task { @MainActor in self?.doPrefs() }
        }
        keys.add(UInt32(kVK_UpArrow), mod) { [weak self] in Task { @MainActor in self?.batchMove(-1) } }
        keys.add(UInt32(kVK_DownArrow), mod) { [weak self] in Task { @MainActor in self?.batchMove(1) } }
        keys.add(UInt32(kVK_Return), mod) { [weak self] in Task { @MainActor in self?.batchClick() } }
        keys.add(UInt32(kVK_ANSI_B), mod) { [weak self] in Task { @MainActor in self?.batch() } }
        keys.add(UInt32(kVK_ANSI_E), mod) { [weak self] in Task { @MainActor in self?.eliminate() } }
        keys.add(UInt32(kVK_ANSI_G), mod) { [weak self] in Task { @MainActor in self?.explain() } }
        keys.add(UInt32(kVK_ANSI_T), mod) { [weak self] in Task { @MainActor in self?.doReport() } }
        keys.add(UInt32(kVK_ANSI_Y), mod) { [weak self] in Task { @MainActor in self?.doReview() } }
        keys.add(UInt32(kVK_ANSI_U), mod) { [weak self] in
            Task { @MainActor in self?.togglePin() }
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

    private func setDisplay(_ d: Display) {
        guard d != display else { return }
        display = d
        config.display = d
        state.dim = false
        if d == .ghost { state.text = ""; state.full = "" }
        applyDisplay()
    }

    private func applyDisplay() {
        state.display = display
        state.hint = config.showHints ? hint : ""
        panel.ignoresMouseEvents = display == .ghost
        statusItem?.isVisible = !(config.hideStatusItem && display == .ghost)
        if let r = corner(display.size.width, display.size.height) {
            panel.setFrame(r, display: true)
        }
        panel.orderFrontRegardless()
        register()
    }

    private func reloadConfig() {
        config = Config.load()
        display = config.display
        applyDisplay()
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
            if display == .ghost, let r = corner(380, 180) { panel.setFrame(r, display: true) }
        } else if display == .ghost, let r = corner(64, 48) {
            state.text = ""
            panel.setFrame(r, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func openPrompt() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if display == .ghost, let r = corner(440, 200) {
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
        case "letter": setDisplay(display.next)
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
        if display == .ghost {
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
        state.letter = ""
        state.shaky = false
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
        prevText = lastText
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
        var body = text.count > 1500
            ? String(text.prefix(400)) + "\n...\n" + String(text.suffix(1100))
            : text
        if !pinnedText.isEmpty {
            body = "Pinned stimulus:\n" + pinnedText + "\n...\n" + String(text.suffix(900))
        }
        let prompt = body + hint
        qStart = Date()
        let wantImage = cfg.attachImage || text.count < 200
        let vision = wantImage ? image.map { Capture.downscale($0, maxWidth: 800) } : nil
        Log.write("solve labels=\(labels.map { $0.0 }.joined()) image=\(vision != nil) chars=\(text.count)")
        if overlap(prevText, text) < 0.3 { await history.clear() }
        let hist = await history.block()
        if !hist.isEmpty { Log.write("hist \(hist.count) chars") }

        let key = Cache.key(prompt + hist, cfg.model)
        if cfg.useCache, let hit = Cache.get(key) {
            await present(parse(hit), labels, g, cfg, cached: true)
            return
        }

        var replies: [Reply] = []
        let n = max(1, cfg.consensusSamples)
        if n == 1 {
            do {
                let raw = try await timeout(120) { try await Model.solve(prompt, image: vision, cfg, history: hist) }
                guard g == gen else { return }
                Log.write("raw \(raw.prefix(300))")
                replies = [parse(raw)]
            } catch {
                if Task.isCancelled { return }
                Log.write("model error: \(error)")
                set(g, describe(error))
                return
            }
        } else {
            var tasks: [Task<Reply?, Never>] = []
            for _ in 0..<n {
                tasks.append(Task {
                    do {
                        let raw = try await self.timeout(120) { try await Model.solve(prompt, image: vision, cfg, history: hist) }
                        return self.parse(raw)
                    } catch { return nil }
                })
            }
            for t in tasks { if let r = await t.value { replies.append(r) } }
            guard g == gen else { return }
        }

        let valid = replies.filter { !$0.answer.isEmpty || $0.letter != nil || !($0.reason ?? "").isEmpty }
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
            i0 = cfg.attachImage ? Capture.downscale(r.image, maxWidth: 800) : nil
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
            set(g, describe(error))
        }
    }

    private func present(_ r: Reply, _ labels: [(String, CGRect)], _ g: Int, _ cfg: Config, cached: Bool) async {
        state.cached = cached
        if let img = lastImage, display == .ghost { sampleContrast(img) }
        let hi = max(cfg.revealMin, cfg.revealMax)
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: cfg.revealMin...hi) * 1_000_000_000))
        guard g == gen else { return }

        var letter = r.letter
        if let l = letter, labels.count >= 2, let i = Resolve.index(l), i >= labels.count {
            letter = Resolve.letters[labels.count - 1]
        }
        let target = r.mode == "mcq" ? Resolve.target(answer: r.answer, letter: letter, boxes: boxes) : nil
        if letter == nil, let t = target { letter = Resolve.letter(for: t.box, labels: labels) }

        var full = r.answer.isEmpty ? (r.reason ?? "") : r.answer
        if let reason = r.reason, !reason.isEmpty { full += "\n\(reason)" }
        if let c = r.confidence { full += "  [\(Int(c * 100))%]" }
        state.full = full
        Log.write("present mode=\(r.mode) letter=\(letter ?? "-") answer=\(r.answer.prefix(60)) target=\(target?.tier ?? "none")")

        state.letter = r.mode == "mcq" ? (letter ?? "?") : String(r.answer.prefix(3))
        state.shaky = (r.confidence ?? 1) < cfg.confidenceFloor
        if display == .ghost {
            set(g, state.letter)
        } else if display == .compact {
            set(g, letter.map { "\($0)  \(r.answer.prefix(70))" } ?? String(r.answer.prefix(80)))
        } else {
            set(g, full.isEmpty ? "(empty) \(r.raw.prefix(120))" : full)
        }

        AnswerLog.record(question: String(lastText.suffix(400)), letter: letter ?? "-", answer: r.answer,
                         confidence: r.confidence ?? 0, tier: target?.tier ?? "none")

        guard r.mode == "mcq", let t = target else {
            if r.mode == "mcq" { Log.write("click: UNRESOLVED") }
            return
        }
        lastTarget = t.box
        Log.write("click: \(t.tier) \(t.text.prefix(40))")
        if let prev = lastTarget { targetStack.append(prev) }
        Capture.click(pixel: jitter(t.box), scale: scale)
        await history.add(lastText, letter ?? "", r.answer, r.reason ?? "")

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

    private func overlap(_ a: String, _ b: String) -> Double {
        let x = Set(a.lowercased().split(separator: " ").filter { $0.count > 3 })
        guard !x.isEmpty else { return 1 }
        let y = Set(b.lowercased().split(separator: " ").filter { $0.count > 3 })
        return Double(x.intersection(y).count) / Double(x.count)
    }

    private func undo() {
        guard let b = targetStack.popLast() else { flash("nothing to undo"); return }
        Capture.click(pixel: jitter(b), scale: scale)
        Log.write("click: undo")
    }

    private func copyAnswer() {
        guard !state.full.isEmpty else { flash("nothing to copy"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.full, forType: .string)
        flash("copied")
    }

    private func describe(_ e: Error) -> String {
        guard case ModelError.http(let code, let body) = e else {
            return "\(e) — press ⌃⌥⌘S to retry"
        }
        switch code {
        case 401, 402: return "Key rejected (\(code)) — check preferences"
        case 429: return "Rate-limited — wait a few seconds, then ⌃⌥⌘S"
        case 503: return "Provider busy — press ⌃⌥⌘S to retry"
        default: return "HTTP \(code) — \(body.prefix(70))"
        }
    }

    private func togglePin() {
        if pinnedText.isEmpty {
            guard lastText.count > 60 else { flash("nothing to pin"); return }
            pinnedText = String(lastText.prefix(700))
            flash("stimulus pinned")
        } else {
            pinnedText = ""
            flash("stimulus unpinned")
        }
        Log.write("pin \(pinnedText.isEmpty ? "off" : "on")")
    }

    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let sec = Int(Date().timeIntervalSince(self.sessionStart))
                let q = Int(Date().timeIntervalSince(self.qStart))
                self.state.elapsed = String(format: "%d:%02d · %ds", sec / 60, sec % 60, q)
            }
        }
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
