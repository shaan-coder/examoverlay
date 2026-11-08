import AppKit
import SwiftUI

enum WizardWindow {
private static var win: NSWindow?

@MainActor static func show(onDone: @escaping () -> Void) {
if let w = win { w.makeKeyAndOrderFront(nil); return }
let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
styleMask: [.titled, .closable], backing: .buffered, defer: false)
w.title = "ExamOverlay Setup"
w.isReleasedWhenClosed = false
w.center()
w.contentView = NSHostingView(rootView: WizardView(finish: {
win?.close(); win = nil; onDone()
}))
win = w
w.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
}
}

struct WizardView: View {
var finish: () -> Void
@State private var step = 0
@State private var screen = false
@State private var ax = false
@State private var key = ""
    @State private var provider = 0
    @State private var endpoint = ""
    @State private var model = ""
@State private var test = ""
@State private var testing = false
private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

var body: some View {
VStack(alignment: .leading, spacing: 14) {
Text(title).font(.system(size: 17, weight: .semibold))
Group {
switch step {
case 0: welcome
case 1: perms
case 2: keyStep
                case 3: practice
default: doneStep
}
}.frame(maxWidth: .infinity, alignment: .leading)
Spacer()
HStack {
if step > 0 { Button("Back") { step -= 1 } }
Spacer()
if step < 4 { Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction)
.disabled(step == 1 && !(screen && ax)) }
else { Button("Done") { finish() }.keyboardShortcut(.defaultAction) }
}
}
.padding(20)
.frame(width: 460, height: 330)
.onReceive(timer) { _ in screen = Doctor.screenGranted; ax = Doctor.axGranted }
.onAppear {
            screen = Doctor.screenGranted; ax = Doctor.axGranted
            let c = Config.load()
            endpoint = c.endpoint.absoluteString
            model = c.model
            if endpoint.contains("groq") { provider = 0 }
            else if endpoint.contains("deepseek") { provider = 1 }
            else if endpoint.contains("venice") { provider = 2 }
        }
}

private var title: String {
["Welcome", "Permissions", "API key", "Ready"][min(step, 3)]
}

private var welcome: some View {
VStack(alignment: .leading, spacing: 10) {
Text("This reads the question on screen, picks an answer, and clicks it.")
Text("Three steps: permissions, an API key, then a practice question.")
Text("During a test you press one key. Everything else is optional.")
}.font(.system(size: 12)).foregroundStyle(.secondary)
}

private var perms: some View {
VStack(alignment: .leading, spacing: 10) {
perm("Screen Recording", screen, .screen)
perm("Accessibility", ax, .access)
Text("Both are needed. Grant them, then come back here — the status updates on its own.")
.font(.system(size: 11)).foregroundStyle(.secondary)
Button("Request both now") { Doctor.requestBoth() }
}
}

private func perm(_ name: String, _ ok: Bool, _ pane: Doctor.Pane) -> some View {
HStack {
Text(ok ? "●" : "○").foregroundStyle(ok ? Color.green : Color.secondary)
Text(name)
Spacer()
if !ok { Button("Open pane") { Doctor.open(pane) }.controlSize(.small) }
}.font(.system(size: 12))
}

private var keyStep: some View {
VStack(alignment: .leading, spacing: 10) {
Text("Paste an API key. Groq's free tier works; so does DeepSeek or Venice.")
.font(.system(size: 12)).foregroundStyle(.secondary)
Picker("Provider", selection: $provider) {
                Text("Groq").tag(0)
                Text("DeepSeek").tag(1)
                Text("Venice").tag(2)
            }.pickerStyle(.segmented)
            .onChange(of: provider) { _, v in applyProvider(v) }
            Text("\(endpoint)  ·  \(model)")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            SecureField("API key", text: $key)
HStack {
Button(testing ? "Testing…" : "Test") { runTest() }.disabled(key.isEmpty || testing)
Text(test).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
}
Button("Save key") { saveKey() }.disabled(key.isEmpty)
}
}

private var practice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practice").font(.system(size: 13, weight: .semibold))
            Text("Which development most directly enabled the Columbian Exchange?")
                .font(.system(size: 11))
            ForEach(["A. The fall of Constantinople",
                     "B. New maritime technology and Atlantic crossings",
                     "C. The Mughal conquest of India",
                     "D. The Protestant Reformation"], id: \.self) { o in
                Text(o).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Expected: B").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var doneStep: some View {
VStack(alignment: .leading, spacing: 10) {
Text("You are set. Press ⌃⌥⌘S on any screen with a question.")
Text("The overlay starts in ghost density — one letter, click-through, dims itself.")
Text("⌃⌥⌘L cycles density. ⌘, opens preferences.")
}.font(.system(size: 12)).foregroundStyle(.secondary)
}

private func applyProvider(_ v: Int) {
        switch v {
        case 0: endpoint = "https://api.groq.com/openai/v1/chat/completions"; model = "qwen/qwen3.8-27b"
        case 1: endpoint = "https://api.deepseek.com/chat/completions"; model = "deepseek-flash"
        default: endpoint = "https://api.venice.ai/api/v1/chat/completions"; model = "llama-3.3-70b"
        }
    }

    private func saveKey() {
var o: [String: Any] = (try? Data(contentsOf: Config.path))
.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
o["endpoint"] = endpoint
        o["model"] = model
        o["apiKey"] = key.trimmingCharacters(in: .whitespacesAndNewlines)
o["onboarded"] = (test == "Works.")
if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted]) {
try? d.write(to: Config.path)
}
test = "Saved."
NotificationCenter.default.post(name: .examOverlayConfigChanged, object: nil)
}

private func runTest() {
testing = true
test = ""
let c = Config.load()
var body: [String: Any] = ["model": model,
"messages": [["role": "user", "content": "say ok"]], "max_tokens": 8]
var req = URLRequest(url: URL(string: endpoint) ?? c.endpoint)
req.httpMethod = "POST"
req.timeoutInterval = 20
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(key.trimmingCharacters(in: .whitespacesAndNewlines))",
forHTTPHeaderField: "Authorization")
if !endpoint.contains("deepseek") { body["reasoning_effort"] = "none" }
req.httpBody = try? JSONSerialization.data(withJSONObject: body)
URLSession.shared.dataTask(with: req) { data, resp, err in
let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
DispatchQueue.main.async {
testing = false
if let err { test = "Failed: \(err.localizedDescription)"; return }
test = (200..<300).contains(code) ? "Works." : "HTTP \(code). Check the key and model."
}
}.resume()
}
}
