import AppKit
import ApplicationServices
import CoreGraphics

enum AXReader {
    private static let roles: Set<String> = [
        "AXStaticText", "AXTextField", "AXTextArea", "AXHeading", "AXLink",
        "AXRadioButton", "AXCheckBox", "AXButton", "AXPopUpButton",
        "AXMenuItem", "AXCell"
    ]

    private static func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
    }

    private static func label(_ e: AXUIElement) -> String {
        for k in ["AXTitle", "AXValue", "AXDescription", "AXPlaceholderValue"] {
            if let s = attr(e, k) as? String, !s.isEmpty { return s }
        }
        return ""
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p),
              AXValueGetValue(sv as! AXValue, .cgSize, &s),
              s.width > 1, s.height > 1 else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func walk(_ e: AXUIElement, _ d: Int, _ out: inout [(String, CGRect)]) {
        guard d < 22, out.count < 900 else { return }
        let role = (attr(e, kAXRoleAttribute) as? String) ?? ""
        if roles.contains(role) {
            let t = label(e).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let f = frame(e) { out.append((t, f)) }
        }
        guard let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for k in kids { walk(k, d + 1, &out) }
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func read(scale: CGFloat) -> (String, [(String, CGRect)])? {
        guard trusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let win = ref else { return nil }
        var raw: [(String, CGRect)] = []
        walk(win as! AXUIElement, 0, &raw)
        guard raw.count >= 6, raw.reduce(0, { $0 + $1.0.count }) >= 120 else { return nil }
        let o = Capture.origin
        let mapped = raw.compactMap { t, f -> (String, CGRect)? in
            let r = CGRect(x: (f.minX - o.x) * scale, y: (f.minY - o.y) * scale,
                           width: f.width * scale, height: f.height * scale)
            return r.width > 2 && r.height > 2 ? (t, r) : nil
        }
        guard mapped.count >= 6 else { return nil }
        let sorted = mapped.sorted { a, b in
            abs(a.1.minY - b.1.minY) < 6 ? a.1.minX < b.1.minX : a.1.minY < b.1.minY
        }
        return (sorted.map(\.0).joined(separator: "\n"), sorted)
    }
}
