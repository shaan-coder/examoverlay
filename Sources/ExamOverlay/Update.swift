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
        var req = URLRequest(url: r.url)
        req.timeoutInterval = 120
        URLSession.shared.downloadTask(with: req) { tmp, _, err in
            DispatchQueue.main.async {
                guard let tmp, let data = try? Data(contentsOf: tmp) else {
                    alert("Download failed", err?.localizedDescription ?? "")
                    return
                }
                guard verify(data, r.sig) else {
                    alert("Bad signature", "Update not installed.")
                    return
                }
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

        let script = dir.appendingPathComponent("apply.sh")
        let dest = Bundle.main.bundlePath
        let body = """
        #!/bin/bash
        sleep 2
        cd "\(dir)"
        /usr/bin/unzip -q -o new.zip
        rm -rf "\(dest)"
        cp -R "\(dir)/ExamOverlay.app" "\(dest)"
        xattr -dr com.apple.quarantine "\(dest)"
        open "\(dest)"
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
