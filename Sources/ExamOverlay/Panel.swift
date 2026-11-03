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
    @Published var letterMode = false
    @Published var onDark = false
    @Published var showChrome = false
    @Published var dim = false
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
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

    private var bare: Bool { state.letterMode && !state.promptShown }

    var body: some View {
        content
            .padding(.horizontal, bare ? 0 : 10)
            .padding(.top, bare ? 0 : 20)
            .padding(.bottom, bare ? 0 : 8)
            .background(bg)
            .padding(bare ? 0 : 4)
            .opacity(bare && state.dim ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.35), value: state.dim)
            .onChange(of: state.promptShown) { _, v in
                if v { DispatchQueue.main.async { focused = true } }
            }
    }

    @ViewBuilder private var bg: some View {
        if !bare {
            RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)) }
        }
    }

    @ViewBuilder private var content: some View {
        if state.promptShown {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.text).font(.system(size: 12)).lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("ask  (/ for commands, ! = no screen)", text: $state.prompt)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { idx = -1; submit() }
                    .onKeyPress(.upArrow) { recall(1); return .handled }
                    .onKeyPress(.downArrow) { recall(-1); return .handled }
                    .onKeyPress(.escape) { cancel(); return .handled }
                    .onAppear { DispatchQueue.main.async { focused = true } }
            }
        } else if state.letterMode {
            Text(state.text.isEmpty ? "·" : state.text)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(state.onDark ? Color.white : Color.black)
                .shadow(color: (state.onDark ? Color.black : Color.white).opacity(0.6), radius: 1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if state.showChrome {
                    HStack(spacing: 6) {
                        Text("ExamOverlay").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
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
            }
        }
    }

    private func recall(_ s: Int) {
        guard !state.history.isEmpty else { return }
        idx = min(state.history.count - 1, max(-1, idx + s))
        state.prompt = idx >= 0 ? state.history[idx] : ""
    }
}
