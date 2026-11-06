// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreVideo
import QuartzCore

/// A drawn, macOS-looking document window packaged exactly like a ScreenCaptureKit capture
/// (window plus native-looking shadow inside one BGRA buffer). It lets every effect preview
/// play immediately, without asking the user to pick one of their real windows first.
@MainActor
enum SampleWindow {
    static let pointSize = CGSize(width: 640, height: 420)
    static let shadowRoom: CGFloat = 60
    static let scale: CGFloat = 2
    /// Where the sample sits on its virtual display, in global Y-down points.
    static let frameOnStage = CGRect(x: 420, y: 260, width: pointSize.width, height: pointSize.height)
    /// Sentinel ID; never a real `CGWindowID`.
    static let windowID: CGWindowID = 0

    private static var cached: CapturedFrame?

    /// The same buffer for the whole process; callers never mutate the pixels.
    static func frame() throws -> CapturedFrame {
        if let cached { return cached }
        let frame = try render()
        cached = frame
        return frame
    }

    private static func render() throws -> CapturedFrame {
        let room = (shadowRoom * scale).rounded()
        let width = Int(pointSize.width * scale + 2 * room), height = Int(pointSize.height * scale + 2 * room)
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                                           kCVPixelBufferMetalCompatibilityKey: true]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { throw CaptureError.emptySample }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: WindowCapture.colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw CaptureError.emptySample
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        // Top-left origin, like a capture.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(in: context, frame: CGRect(x: shadowRoom, y: shadowRoom, width: pointSize.width, height: pointSize.height),
             dark: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let windowRect = CGRect(x: room, y: room, width: pointSize.width * scale, height: pointSize.height * scale)
        return CapturedFrame(windowID: windowID, pixelBuffer: buffer, pointSize: pointSize, windowRect: windowRect,
                             shadow: ShadowInsets(left: 40, top: 28, right: 40, bottom: 56), capturedAt: CACurrentMediaTime())
    }

    private static func draw(in context: CGContext, frame: CGRect, dark: Bool) {
        let path = CGPath(roundedRect: frame, cornerWidth: 11, cornerHeight: 11, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 24), blur: 40, color: CGColor(gray: 0, alpha: dark ? 0.6 : 0.4))
        context.setFillColor(CGColor(gray: dark ? 0.16 : 1, alpha: 1))
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        let background = dark ? CGColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1) : CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        context.setFillColor(background)
        context.fill(frame)

        // Sidebar.
        let sidebarWidth: CGFloat = 170
        context.setFillColor(dark ? CGColor(red: 0.21, green: 0.21, blue: 0.24, alpha: 1) : CGColor(red: 0.90, green: 0.91, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: sidebarWidth, height: frame.height))

        // Title bar.
        let titleHeight: CGFloat = 38
        context.setFillColor(dark ? CGColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1) : CGColor(red: 0.91, green: 0.91, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: titleHeight))
        context.setFillColor(CGColor(gray: dark ? 0.1 : 0.78, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.minY + titleHeight - 0.5, width: frame.width, height: 0.5))
        for (index, color) in [(0.99, 0.37, 0.34), (0.99, 0.74, 0.18), (0.26, 0.78, 0.29)].enumerated() {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: frame.minX + 14 + CGFloat(index) * 20, y: frame.minY + 13, width: 12, height: 12))
        }
        // Title text stand-in.
        context.setFillColor(CGColor(gray: dark ? 0.7 : 0.35, alpha: 1))
        context.fill(CGRect(x: frame.midX - 50, y: frame.minY + 15, width: 100, height: 8))

        // Sidebar rows.
        for row in 0..<11 {
            let y = frame.minY + titleHeight + 18 + CGFloat(row) * 30
            if row == 2 {
                context.setFillColor(CGColor(red: 0.20, green: 0.48, blue: 0.98, alpha: 0.9))
                context.addPath(CGPath(roundedRect: CGRect(x: frame.minX + 10, y: y - 7, width: sidebarWidth - 20, height: 24), cornerWidth: 5, cornerHeight: 5, transform: nil))
                context.fillPath()
            }
            context.setFillColor(CGColor(gray: row == 2 ? 1 : (dark ? 0.72 : 0.32), alpha: 1))
            context.fillEllipse(in: CGRect(x: frame.minX + 20, y: y, width: 10, height: 10))
            context.fill(CGRect(x: frame.minX + 38, y: y + 1, width: 90 - CGFloat((row * 37) % 45), height: 8))
        }

        // Content: hero cards and paragraph lines.
        let contentX = frame.minX + sidebarWidth + 26
        let cards: [(CGFloat, CGFloat, CGFloat)] = [(0.22, 0.47, 0.96), (0.96, 0.44, 0.27), (0.27, 0.72, 0.46), (0.64, 0.36, 0.86)]
        for (index, card) in cards.enumerated() {
            let rect = CGRect(x: contentX + CGFloat(index) * 108, y: frame.minY + titleHeight + 24, width: 94, height: 94)
            context.setFillColor(CGColor(red: card.0, green: card.1, blue: card.2, alpha: 1))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
            context.setFillColor(CGColor(gray: 1, alpha: 0.85))
            context.fill(CGRect(x: rect.minX + 12, y: rect.maxY - 26, width: 50 - CGFloat(index * 7), height: 7))
            context.fill(CGRect(x: rect.minX + 12, y: rect.maxY - 15, width: 32, height: 5))
        }
        context.setFillColor(CGColor(gray: dark ? 0.82 : 0.2, alpha: 1))
        context.fill(CGRect(x: contentX, y: frame.minY + titleHeight + 140, width: 180, height: 11))
        context.setFillColor(CGColor(gray: dark ? 0.6 : 0.42, alpha: 1))
        for line in 0..<9 {
            context.fill(CGRect(x: contentX, y: frame.minY + titleHeight + 166 + CGFloat(line) * 19,
                                width: 420 - CGFloat((line * 71) % 150), height: 7))
        }
        context.restoreGState()
    }
}
