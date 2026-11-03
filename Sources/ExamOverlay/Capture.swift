import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

/// All rects produced here are image pixels with a top-left origin. click()
/// consumes exactly that space and does its own conversion.
enum Capture {
    static var origin: CGPoint {
        NSScreen.screens.reduce(CGPoint(x: CGFloat.greatestFiniteMagnitude,
                                        y: CGFloat.greatestFiniteMagnitude)) {
            CGPoint(x: min($0.x, $1.frame.minX), y: min($0.y, $1.frame.minY))
        }
    }

    static func click(pixel: CGPoint, scale: CGFloat) {
        let o = origin
        let p = CGPoint(x: o.x + pixel.x / scale, y: o.y + pixel.y / scale)
        CGWarpMouseCursorPosition(p)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func screen() async -> (image: CGImage, scale: CGFloat)? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              !content.displays.isEmpty else { return nil }
        let own = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let union = content.displays.reduce(CGRect.null) {
            $0.union(CGRect(x: $1.frame.minX, y: $1.frame.minY,
                            width: CGFloat($1.width) / scale, height: CGFloat($1.height) / scale))
        }
        let w = Int(union.width * scale), h = Int(union.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }

        for d in content.displays {
            let filter = SCContentFilter(display: d, excludingWindows: own)
            let cfg = SCStreamConfiguration()
            cfg.width = d.width
            cfg.height = d.height
            cfg.showsCursor = false
            cfg.colorSpaceName = CGColorSpace.sRGB
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            else { continue }
            let f = d.frame
            ctx.draw(img, in: CGRect(x: (f.minX - union.minX) * scale,
                                     y: (union.maxY - f.maxY) * scale,
                                     width: f.width * scale, height: f.height * scale))
        }
        guard let out = ctx.makeImage() else { return nil }
        return (out, scale)
    }

    static func text(in img: CGImage, languages: [String]) -> (String, [(String, CGRect)]) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = languages
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])

        let w = CGFloat(img.width), h = CGFloat(img.height)
        var out: [(String, CGRect)] = []
        for obs in req.results ?? [] {
            guard let c = obs.topCandidates(1).first else { continue }
            let bb = obs.boundingBox
            out.append((c.string, CGRect(x: bb.minX * w, y: (1 - bb.maxY) * h,
                                         width: bb.width * w, height: bb.height * h)))
        }
        out.sort { $0.1.minY < $1.1.minY }
        return (out.map { $0.0 }.joined(separator: "\n"), out)
    }

    static func luminance(_ img: CGImage, in r: CGRect) -> CGFloat {
        guard let crop = img.cropping(to: r.integral) else { return 128 }
        let w = max(1, min(crop.width, 64)), h = max(1, min(crop.height, 64))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 128 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: buf.count, by: 4) {
            sum += 0.299 * Double(buf[i]) + 0.587 * Double(buf[i + 1]) + 0.114 * Double(buf[i + 2])
        }
        return CGFloat(sum / Double(w * h))
    }

    static func downscale(_ img: CGImage, maxWidth: Int) -> CGImage {
        guard img.width > maxWidth else { return img }
        let w = maxWidth
        let h = max(1, Int(CGFloat(img.height) * CGFloat(w) / CGFloat(img.width)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }

    static func png(_ img: CGImage, maxWidth: Int = 1100) -> Data? {
        let scaled = downscale(img, maxWidth: maxWidth)
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}
