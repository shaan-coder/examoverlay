import AppKit
import SwiftUI

enum PrefsWindow {
private static var win: NSWindow?

@MainActor static func show() {
if let w = win { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
styleMask: [.titled, .closable], backing: .buffered, defer: false)
w.title = "ExamOverlay Preferences"
w.isReleasedWhenClosed = false
w.center()
w.contentView = NSHostingView(rootView: SettingsView())
win = w
w.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
}
}

@MainActor
final class PrefsModel: ObservableObject {
@Published var endpoint = ""
@Published var model = ""
@Published var apiKey = ""
@Published var fallbackEndpoint = ""
@Published var fallbackModel = ""
@Published var fallbackApiKey = ""
@Published var maxTokens = 300
@Published var temperature = 0.1
@Published var attachImage = true
@Published var useCache = true
@Published var autoSave = false
@Published var display = Display.ghost
@Published var confidenceFloor = 0.55
@Published var revealMin = 0.6
@Published var revealMax = 1.2
@Published var clickThrough = true
@Published var hideStatusItem = true
@Published var showHints = true
@Published var ocrLanguages = "en-US, es-ES"
@Published var saved = false

init() {
let c = Config.load()
endpoint = c.endpoint.absoluteString
model = c.model
apiKey = c.apiKey
fallbackEndpoint = c.fallbackEndpoint?.absoluteString ?? ""
fallbackModel = c.fallbackModel
fallbackApiKey = c.fallbackApiKey
maxTokens = c.maxTokens
temperature = c.temperature
attachImage = c.attachImage
useCache = c.useCache
autoSave = c.autoSave
display = c.display
confidenceFloor = c.confidenceFloor
revealMin = c.revealMin
revealMax = c.revealMax
clickThrough = c.clickThrough
hideStatusItem = c.hideStatusItem
showHints = c.showHints
ocrLanguages = c.ocrLanguages.joined(separator: ", ")
}

func save() {
var o: [String: Any] = (try? Data(contentsOf: Config.path))
.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
o["endpoint"] = endpoint
o["model"] = model
o["apiKey"] = apiKey
o["fallbackEndpoint"] = fallbackEndpoint
o["fallbackModel"] = fallbackModel
o["fallbackApiKey"] = fallbackApiKey
o["maxTokens"] = maxTokens
o["temperature"] = temperature
o["attachImage"] = attachImage
o["useCache"] = useCache
o["autoSave"] = autoSave
o["display"] = display.rawValue
o["confidenceFloor"] = confidenceFloor
o["revealMin"] = revealMin
o["revealMax"] = revealMax
o["clickThrough"] = clickThrough
o["hideStatusItem"] = hideStatusItem
o["showHints"] = showHints
o["ocrLanguages"] = ocrLanguages.split(separator: ",")
.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
try? d.write(to: Config.path)
}
saved = true
NotificationCenter.default.post(name: .examOverlayConfigChanged, object: nil)
}
}

extension Notification.Name {
static let examOverlayConfigChanged = Notification.Name("examOverlayConfigChanged")
}

struct SettingsView: View {
@StateObject private var m = PrefsModel()

var body: some View {
VStack(spacing: 0) {
TabView {
general.tabItem { Text("General") }
keys.tabItem { Text("Keys") }
model.tabItem { Text("Model") }
display.tabItem { Text("Display") }
advanced.tabItem { Text("Advanced") }
}.padding(14)
Divider()
HStack {
Text(m.saved ? "Saved" : "").font(.system(size: 11)).foregroundStyle(.secondary)
Spacer()
Button("Open config file") { NSWorkspace.shared.open(Config.path) }
Button("Save") { m.save() }.keyboardShortcut("s")
}.padding(12)
}.frame(width: 520, height: 470)
}

private var general: some View {
Form {
Toggle("Start in ghost density", isOn: Binding(
get: { m.display == .ghost }, set: { m.display = $0 ? .ghost : .full }))
Toggle("Show hint bar", isOn: $m.showHints)
Toggle("Overlay ignores clicks", isOn: $m.clickThrough)
Toggle("Hide menu bar icon in ghost", isOn: $m.hideStatusItem)
Toggle("Save screenshots per question", isOn: $m.autoSave)
}.formStyle(.grouped)
}

private var keys: some View {
Form {
Section("Global") {
row("Solve", "⌃⌥⌘S, or 8 in ghost")
row("Cycle density", "⌃⌥⌘L")
row("Show / hide overlay", "right shift tap, ⌃⌥⌘H")
row("Fix — click next row down", "⌃⌥⌘J")
row("Undo last click", "⌃⌥⌘Z")
row("Copy answer", "⌃⌥⌘C")
row("Eliminate two options", "⌃⌥⌘E")
                row("Explain current answer", "⌃⌥⌘G")
                row("Review session", "⌃⌥⌘Y")
                row("Ask", "⌃⌥⌘P")
row("Panic — hide and cancel", "⌃⌥⌘X")
}
}.formStyle(.grouped)
}

private func row(_ a: String, _ b: String) -> some View {
HStack { Text(a); Spacer(); Text(b).foregroundStyle(.secondary).font(.system(size: 11)) }
}

private var model: some View {
Form {
Section("Primary") {
TextField("Endpoint", text: $m.endpoint)
TextField("Model", text: $m.model)
SecureField("API key", text: $m.apiKey)
}
Section("Fallback") {
TextField("Endpoint", text: $m.fallbackEndpoint)
TextField("Model", text: $m.fallbackModel)
SecureField("API key", text: $m.fallbackApiKey)
}
Section {
Stepper("Max tokens \(m.maxTokens)", value: $m.maxTokens, in: 100...4000, step: 100)
HStack { Text("Temperature"); Slider(value: $m.temperature, in: 0...1); Text(String(format: "%.2f", m.temperature)) }
}
}.formStyle(.grouped)
}

private var display: some View {
Form {
Picker("Default density", selection: $m.display) {
Text("Ghost").tag(Display.ghost); Text("Compact").tag(Display.compact); Text("Full").tag(Display.full)
}.pickerStyle(.segmented)
HStack { Text("Confidence floor"); Slider(value: $m.confidenceFloor, in: 0...1); Text(String(format: "%.2f", m.confidenceFloor)) }
HStack { Text("Reveal min"); Slider(value: $m.revealMin, in: 0...3); Text(String(format: "%.1fs", m.revealMin)) }
HStack { Text("Reveal max"); Slider(value: $m.revealMax, in: 0...4); Text(String(format: "%.1fs", m.revealMax)) }
}.formStyle(.grouped)
}

private var advanced: some View {
Form {
TextField("OCR languages", text: $m.ocrLanguages)
Toggle("Attach screenshot to requests", isOn: $m.attachImage)
Toggle("Use answer cache", isOn: $m.useCache)
Section {
Button("Run doctor") {
let a = NSAlert()
a.messageText = "Status"
a.informativeText = Doctor.summary()
a.runModal()
}
Button("Clear cache and context") { Cache.clear(); Task { await history.clear() } }
}
}.formStyle(.grouped)
}
}
