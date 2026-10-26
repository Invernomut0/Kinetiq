// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ScreenCaptureKit

/// One element of the desktop (app window, Dock, menu bar, widget, desktop icons) as a picture.
struct SnapshotWindow {
    let id: CGWindowID
    /// Global display coordinates (origin top-left of the primary display, y down).
    let frame: CGRect
    let image: CGImage
    /// Name of the owning application ("Dock" for the Dock).
    let owner: String?
}

enum SnapshotError: Error {
    case permissionDenied
    case nothingToCapture
}

/// Saves what is on the screens with ScreenCaptureKit (needs Screen Recording permission): every desktop element as a
/// separate picture, and the wallpaper alone.
@MainActor
enum DesktopSnapshot {
    private static let colorSpace = CGColorSpace.sRGB

    /// The front-most `limit` elements, ordered back to front. Full-screen layers such as the Dock are cropped to
    /// the area that actually has content.
    static func capture(limit: Int = 24) async throws -> [SnapshotWindow] {
        guard CGPreflightScreenCaptureAccess() else { throw SnapshotError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = elementIDs().compactMap { byID[$0] }.prefix(limit)

        var captured: [SnapshotWindow] = []
        for window in ordered {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let pixelScale = min(CGFloat(filter.pointPixelScale), 2)
            configuration.width = max(1, Int(window.frame.width * pixelScale))
            configuration.height = max(1, Int(window.frame.height * pixelScale))
            configuration.colorSpaceName = colorSpace
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
                  let trimmed = trimmed(SnapshotWindow(id: window.windowID, frame: window.frame, image: image,
                                                       owner: window.owningApplication?.applicationName)) else { continue }
            captured.append(trimmed)
        }
        guard !captured.isEmpty else { throw SnapshotError.nothingToCapture }
        return captured.reversed()
    }

    /// The wallpaper of a screen, without windows, menu bar, Dock or icons. Nil when it cannot be captured.
    static func wallpaper(for screen: NSScreen) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess(),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == id }) else { return fileWallpaper(for: screen) }
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        // Everything at the level of the desktop icons or above is left out: what remains is the picture behind it all.
        let excluded = content.windows.filter { $0.windowLayer >= iconLevel }
        guard content.windows.contains(where: { $0.windowLayer < iconLevel }) else { return fileWallpaper(for: screen) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = min(CGFloat(filter.pointPixelScale), 2)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
        config.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
        config.colorSpaceName = colorSpace
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return fileWallpaper(for: screen)
        }
        return image
    }

    /// The desktop picture file (aspect fill) or, failing that, a neutral gradient.
    private static func fileWallpaper(for screen: NSScreen) -> CGImage? {
        let scale = min(screen.backingScaleFactor, 2)
        let width = max(Int(screen.frame.width * scale), 1), height = max(Int(screen.frame.height * scale), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let source = NSWorkspace.shared.desktopImageURL(for: screen)
            .flatMap { NSImage(contentsOf: $0) }
            .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        if let source {
            let fill = max(CGFloat(width) / CGFloat(source.width), CGFloat(height) / CGFloat(source.height))
            let w = CGFloat(source.width) * fill, h = CGFloat(source.height) * fill
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
        } else if let gradient = CGGradient(colorsSpace: space,
                                            colors: [CGColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1), CGColor(red: 0.30, green: 0.42, blue: 0.58, alpha: 1)] as CFArray,
                                            locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: CGFloat(height)), options: [])
        }
        return context.makeImage()
    }

    /// Window IDs of every on-screen element worth saving, front to back: app windows, the Dock, the menu bar, widgets and
    /// desktop icons. Wallpaper layers, our own windows and the menu bar backdrop are left out.
    private static func elementIDs() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let lowestLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
        let backdropLayer = lowestLayer + 1
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [CGWindowID] = []
        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer >= lowestLayer,
                  !(layer == backdropLayer && (info[kCGWindowOwnerName as String] as? String) == "Window Server"),
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownPID,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.1,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  frame.width >= 40, frame.height >= 20
            else { continue }
            result.append(number)
        }
        return result
    }

    /// Crops a capture to the bounding box of its non-transparent pixels; nil when it is fully transparent.
    private static func trimmed(_ window: SnapshotWindow) -> SnapshotWindow? {
        let width = window.image.width, height = window.image.height
        let step = 4
        let w = max(1, width / step), h = max(1, height / step)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return window }
        context.interpolationQuality = .low
        context.draw(window.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let alpha = data.bindMemory(to: UInt8.self, capacity: w * h)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where alpha[y * w + x] > 24 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let x0 = max(0, (minX - 1) * step), y0 = max(0, (minY - 1) * step)
        let x1 = min(width, (maxX + 2) * step), y1 = min(height, (maxY + 2) * step)
        let crop = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        if crop.width >= CGFloat(width) - 1, crop.height >= CGFloat(height) - 1 { return window }
        guard let image = window.image.cropping(to: crop) else { return window }
        let sx = window.frame.width / CGFloat(width), sy = window.frame.height / CGFloat(height)
        let frame = CGRect(x: window.frame.minX + crop.minX * sx, y: window.frame.minY + crop.minY * sy,
                           width: crop.width * sx, height: crop.height * sy)
        return SnapshotWindow(id: window.id, frame: frame, image: image, owner: window.owner)
    }
}
