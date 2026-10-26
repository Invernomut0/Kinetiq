// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore

/// Real AppKit rendering of a window (a real `NSWindow` frame with its standard buttons and text in the system font)
/// and of a Dock bar with the real icons of system apps: realistic input for `UIObjectExtractor` and `ChaosWorld`.
@MainActor
enum ChaosFixture {
    private static func bitmap(_ size: CGSize, scale: CGFloat, draw: () -> Void) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size   // before the context exists, so drawing is in points
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    static let lines = [
        "The quick brown fox jumps over the lazy dog",
        "Pack my box with five dozen liquor jugs",
        "Sphinx of black quartz, judge my vow",
        "How vexingly quick daft zebras jump",
    ]

    /// A document-like window: title bar with the three standard buttons, a heading and lines of text.
    static func window(scale: CGFloat = 2) -> (image: CGImage, size: CGSize)? {
        _ = NSApplication.shared
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 292), styleMask: style, backing: .buffered, defer: false)
        guard let frameView = w.contentView?.superview else { return nil }
        let size = frameView.bounds.size
        guard let image = bitmap(size, scale: scale, draw: {
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            if let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                rep.draw(in: NSRect(origin: .zero, size: size))
            }
            // The document area is light whatever the system appearance is.
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size.width, height: 292).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]
            for (i, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: attributes).draw(at: NSPoint(x: 24, y: size.height - 80 - CGFloat(i) * 26))
            }
            let heading: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor(calibratedRed: 0.1, green: 0.25, blue: 0.6, alpha: 1)]
            NSAttributedString(string: "Kinetiq", attributes: heading).draw(at: NSPoint(x: 24, y: size.height - 190))
        }) else { return nil }
        return (image, size)
    }

    static let dockApps = [
        "/System/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Calendar.app", "/System/Applications/Notes.app",
        "/System/Applications/Music.app", "/System/Applications/Maps.app", "/System/Applications/Photos.app", "/System/Applications/Preview.app",
        "/System/Applications/Utilities/Terminal.app", "/System/Applications/Calculator.app",
    ]

    /// A translucent Dock bar with the icons of system apps.
    static func dock(scale: CGFloat = 2) -> (image: CGImage, size: CGSize)? {
        let icon: CGFloat = 56, gap: CGFloat = 10
        let size = CGSize(width: CGFloat(dockApps.count) * (icon + gap) + gap, height: icon + 20)
        guard let image = bitmap(size, scale: scale, draw: {
            NSColor(calibratedWhite: 0.85, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 16, yRadius: 16).fill()
            for (i, path) in dockApps.enumerated() {
                NSWorkspace.shared.icon(forFile: path).draw(in: NSRect(x: gap + CGFloat(i) * (icon + gap), y: 10, width: icon, height: icon))
            }
        }) else { return nil }
        return (image, size)
    }

    /// The window and the Dock on a 1100 x 760 pt screen, plus a second window overlapping the first one.
    static func scene(extra: Bool = false) -> (scene: ChaosScene, screen: SIMD2<Float>)? {
        guard let window = window(), let dock = dock(),
              let w = UIObjectExtractor.extract(from: window.image, size: window.size),
              let d = UIObjectExtractor.extract(from: dock.image, size: dock.size, role: .dock) else { return nil }
        var inputs = [ChaosWindowInput(frame: CGRect(origin: CGPoint(x: 120, y: 90), size: window.size), extraction: w)]
        if extra {
            inputs.append(ChaosWindowInput(frame: CGRect(origin: CGPoint(x: 300, y: 150), size: window.size), extraction: w))
        }
        inputs.append(ChaosWindowInput(frame: CGRect(origin: CGPoint(x: 220, y: 670), size: dock.size), extraction: d))
        return (ChaosSceneBuilder.build(windows: inputs), SIMD2(1100, 760))
    }
}
