// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ScreenCaptureKit

/// A frozen picture of every screen, taken without one window (and without menus, the Dock and our own overlays),
/// shown over the real thing for a moment. Whatever the system does to that window in the meantime (the minimize
/// animation shrinks the real window towards the Dock) happens underneath, out of sight.
@MainActor
final class ScreenShield {
    private var windows: [NSWindow] = []

    /// Captures all screens as they look without the windows in `hiding`.
    static func capture(hiding windowIDs: [CGWindowID]) async -> ScreenShield? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Everything above the normal windows (menu bar, Dock, menus) is drawn live over the shield: keep it out of the picture.
        let hidden = content.windows.filter {
            windowIDs.contains($0.windowID) || $0.windowLayer > 0 || $0.owningApplication?.processID == ownPID
        }

        let shield = ScreenShield()
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
            }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: hidden)
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = Int((CGFloat(display.width) * scale).rounded())
            config.height = Int((CGFloat(display.height) * scale).rounded())
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.displayP3
            config.showsCursor = false
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
            shield.windows.append(makeWindow(for: screen, image: image))
        }
        return shield.windows.isEmpty ? nil : shield
    }

    func show() {
        windows.forEach { $0.orderFrontRegardless() }
    }

    func hide() {
        windows.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        windows = []
    }

    private static func makeWindow(for screen: NSScreen, image: CGImage) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        view.layer?.isOpaque = true
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        return window
    }
}
