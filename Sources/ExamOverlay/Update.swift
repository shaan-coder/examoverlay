import AppKit
import CryptoKit
import Foundation

enum Update {
    static let manifest = URL(string: "https://raw.githubusercontent.com/shaan-coder/examoverlay/main/versions.json")!
    static let pubKey = "ENFVIiTU0TxgTnnC4WVFyX0PBoRdKELCINQ1Ca2eTaY="

    struct Release {
        let version: String
        let url: URL
        let notes: String
        let sig: String
    }

    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    static func check(quiet: Bool) {
        var req = URLRequest(url: manifest)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        req.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data,
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let v = o["version"] as? String,
                      let u = (o["url"] as? String).flatMap(URL.init),
                      let s = o["sig"] as? String else {
                    if !quiet { alert("Update check failed", err?.localizedDescription ?? "bad manifest") }
                    return
                }
                guard newer(v, than: current) else {
                    if !quiet { alert("Up to date", "You have \(current).") }
                    return
                }
                let notes = o["notes"] as? String ?? ""
                let a = NSAlert()
                a.messageText = "ExamOverlay \(v) is available"
                a.informativeText = notes + "\n\nPermissions carry over. Grant them again only if macOS asks."
                a.addButton(withTitle: "Install")
                a.addButton(withTitle: "Later")
                if a.runModal() == .alertFirstButtonReturn {
                    install(Release(version: v, url: u, notes: notes, sig: s))
                }
            }
        }.resume()
    }

    private static func newer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    private static func alert(_ t: String, _ b: String) {
        let a = NSAlert()
        a.messageText = t
        a.informativeText = b
        a.runModal()
    }

    private static func install(_ r: Release) {
        Log.write("update: install \(r.version) from \(r.url.absoluteString)")
        var req = URLRequest(url: r.url)
        req.timeoutInterval = 120
        URLSession.shared.downloadTask(with: req) { tmp, _, err in
            DispatchQueue.main.async {
                guard let tmp, let data = try? Data(contentsOf: tmp) else {
                    alert("Download failed", err?.localizedDescription ?? "")
                    return
                }
                Log.write("update: downloaded \(data.count) bytes")
                guard verify(data, r.sig) else {
                    Log.write("update: signature failed")
                    alert("Bad signature", "Update not installed.")
                    return
                }
                Log.write("update: signature ok, staging")
                stage(data)
            }
        }.resume()
    }

    private static func verify(_ data: Data, _ sig: String) -> Bool {
        guard let raw = Data(base64Encoded: pubKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let s = Data(base64Encoded: sig) else { return false }
        return (try? key.isValidSignature(s, for: data)) ?? false
    }

    private static func stage(_ zip: Data) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("examoverlay-update")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? zip.write(to: dir.appendingPathComponent("new.zip"))

        let dirPath = dir.path(percentEncoded: false)
        let script = dir.appendingPathComponent("apply.sh")
        let dest = Bundle.main.bundlePath
        let body = """
        #!/bin/bash
        exec > /tmp/examoverlay-update.log 2>&1
        set -x
        sleep 2
        cd "\(dirPath)" || exit 1
        /usr/bin/unzip -q -o new.zip || exit 1
        APP="\(dirPath)/ExamOverlay.app"
        [ -d "$APP" ] || APP="\(dirPath)/build/ExamOverlay.app"
        [ -d "$APP" ] || exit 1
        DEST="\(dest)"
        TMP="$DEST.new"
        rm -rf "$TMP"
        cp -R "$APP" "$TMP" || exit 1
        xattr -dr com.apple.quarantine "$TMP" 2>/dev/null
        rm -rf "$DEST"
        mv "$TMP" "$DEST"
        open "$DEST"
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "nohup /bin/bash '\(script.path)' > /tmp/examoverlay-update.log 2>&1 &"]
        Log.write("update: script \(script.path), dest \(dest)")
        do { try p.run() } catch { Log.write("update: spawn failed \(error)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
    }
}
