import AppKit
import SwiftUI

@MainActor
final class UIState: ObservableObject {
@Published var text = ""
@Published var full = ""
@Published var busy = false
@Published var prompt = ""
@Published var promptShown = false
@Published var asked: String?
@Published var history: [String] = []
@Published var cached = false
@Published var display = Display.ghost
@Published var letter = ""
@Published var shaky = false
@Published var hint = ""
@Published var onDark = false
@Published var showChrome = false
@Published var dim = false
    @Published var auto = false
    @Published var autoWait = ""
    @Published var autoStatus = ""
    @Published var autoStatusOn = false
    @Published var eliminated: [String] = []
    @Published var elapsed = ""
}

final class Panel: NSPanel {
override var canBecomeKey: Bool { true }

init() {
super.init(contentRect: NSRect(x: 0, y: 0, width: 56, height: 44),
styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow],
backing: .buffered, defer: false)
isFloatingPanel = true
level = .floating
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
hidesOnDeactivate = false
becomesKeyOnlyIfNeeded = true
isMovableByWindowBackground = true
titleVisibility = .hidden
titlebarAppearsTransparent = true
sharingType = .none
isOpaque = false
backgroundColor = .clear
hasShadow = false
animationBehavior = .none
}
}

struct Overlay: View {
@ObservedObject var state: UIState
var submit: () -> Void
var cancel: () -> Void
@FocusState var focused: Bool
@State var idx = -1

private var ghost: Bool { state.display == .ghost && !state.promptShown }

var body: some View {
content
.padding(.horizontal, ghost ? 0 : 10)
.padding(.top, ghost ? 0 : 16)
.padding(.bottom, ghost ? 0 : 7)
.background(bg)
.padding(ghost ? 0 : 4)
.opacity(ghost && state.dim ? 0.25 : 1)
.animation(.easeInOut(duration: 0.3), value: state.dim)
.onChange(of: state.promptShown) { _, v in
if v { DispatchQueue.main.async { focused = true } }
}
}

@ViewBuilder private var bg: some View {
if !ghost {
RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
.overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)) }
}
}

private var chip: String {
state.shaky && !state.letter.isEmpty ? "⚠" : (state.letter.isEmpty ? "·" : state.letter)
}

@ViewBuilder private var content: some View {
if state.promptShown {
VStack(alignment: .leading, spacing: 6) {
Text(state.text).font(.system(size: 12)).lineLimit(5)
.frame(maxWidth: .infinity, alignment: .leading)
TextField("ask (/ for commands, ! = no screen)", text: $state.prompt)
.textFieldStyle(.roundedBorder).font(.system(size: 12))
.focused($focused)
.onSubmit { idx = -1; submit() }
.onKeyPress(.upArrow) { recall(1); return .handled }
.onKeyPress(.downArrow) { recall(-1); return .handled }
.onKeyPress(.escape) { cancel(); return .handled }
}
} else if state.display == .ghost {
Text(chip)
.font(.system(size: state.shaky ? 17 : 22, weight: .bold))
.foregroundStyle(state.onDark ? Color.white : Color.black)
.shadow(color: (state.onDark ? Color.black : Color.white).opacity(0.6), radius: 1.5)
.frame(maxWidth: .infinity, maxHeight: .infinity)
} else if state.display == .compact {
HStack(alignment: .top, spacing: 7) {
VStack(alignment: .leading, spacing: 1) {
                    Text(chip).font(.system(size: 15, weight: .bold))
                    if state.autoStatusOn && !state.autoStatus.isEmpty {
                        Text(state.autoStatus).font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
.foregroundStyle(state.shaky ? Color.orange : Color.primary)
Text(state.text).font(.system(size: 12)).lineLimit(2)
.frame(maxWidth: .infinity, alignment: .leading)
if state.busy { ProgressView().controlSize(.mini) }
}
} else {
VStack(alignment: .leading, spacing: 4) {
if state.showChrome {
HStack(spacing: 6) {
Text("ExamOverlay")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        if state.auto {
                            Text("AUTO").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.25)).clipShape(Capsule())
                        }
                        
if state.cached {
Text("cached").font(.system(size: 9, weight: .semibold))
.padding(.horizontal, 5).padding(.vertical, 1)
.background(Color.secondary.opacity(0.18)).clipShape(Capsule())
}
Spacer()
if state.busy { ProgressView().controlSize(.mini) }
}
}
if let a = state.asked, !a.isEmpty {
Text("Q: \(a)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
}
ScrollView {
Text(state.text).font(.system(size: 13)).textSelection(.enabled)
.frame(maxWidth: .infinity, alignment: .leading)
}.scrollIndicators(.hidden)
if state.autoStatusOn && !state.autoStatus.isEmpty {
                    Text(state.autoStatus).font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1)
                }
                if !state.hint.isEmpty {
if !state.eliminated.isEmpty {
                    Text("✗ " + state.eliminated.joined(separator: "  "))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(state.elapsed).font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(state.elapsed).font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(state.hint).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
}
}
}
}

private func recall(_ s: Int) {
guard !state.history.isEmpty else { return }
idx = min(state.history.count - 1, max(-1, idx + s))
state.prompt = idx >= 0 ? state.history[idx] : ""
}
}
