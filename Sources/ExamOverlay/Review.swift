import AppKit
import SwiftUI

struct ReviewRow: Identifiable {
    let id = UUID()
    let letter: String
    let answer: String
    let confidence: Double
    let question: String
}

@MainActor
final class ReviewModel: ObservableObject {
    @Published var rows: [ReviewRow] = []
    @Published var status = ""

    func load() {
        let since = Calendar.current.startOfDay(for: Date())
        var seen = Set<String>()
        var out: [ReviewRow] = []
        for o in AnswerLog.entries(since: since) {
            let a = (o["answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard a.count > 3 else { continue }
            let k = String(a.lowercased().prefix(60))
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(ReviewRow(letter: o["letter"] as? String ?? "?",
                                 answer: a,
                                 confidence: o["confidence"] as? Double ?? 0,
                                 question: String((o["q"] as? String ?? "").suffix(140))))
        }
        rows = out
        status = "\(out.count) answers"
    }

    var plain: String {
        rows.enumerated().map { i, r in
            "\(i + 1). \(r.letter). \(r.answer)  (\(Int(r.confidence * 100))%)"
        }.joined(separator: "\n")
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
        status = "copied \(rows.count)"
    }

    func saveText() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "answers.txt"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        try? plain.write(to: u, atomically: true, encoding: .utf8)
        status = "saved"
    }
}

enum ReviewWindow {
    private static var win: NSWindow?

    @MainActor static func show() {
        if let w = win {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Session review"
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: ReviewView())
        win = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ReviewView: View {
    @StateObject private var m = ReviewModel()

    var body: some View {
        VStack(spacing: 0) {
            List(m.rows) { r in
                HStack(alignment: .top, spacing: 8) {
                    Text(r.letter).font(.system(size: 13, weight: .bold))
                        .frame(width: 16, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.answer).font(.system(size: 12))
                        Text(r.question).font(.system(size: 9))
                            .foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(Int(r.confidence * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(r.confidence < 0.55 ? .orange : .secondary)
                }
            }
            Divider()
            HStack {
                Text(m.status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { m.load() }
                Button("Save…") { m.saveText() }
                Button("Copy all") { m.copy() }.keyboardShortcut("c")
            }.padding(10)
        }
        .frame(width: 460, height: 480)
        .onAppear { m.load() }
    }
}
