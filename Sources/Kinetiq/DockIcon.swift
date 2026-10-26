// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices

/// Where an app's icon is in the Dock, asked to the Dock itself through Accessibility.
enum DockIcon {
    private static let iconSize: CGFloat = 56

    /// Frame of the icon of the app with `pid` in global CoreGraphics coordinates (origin at the top left of the main
    /// screen). Falls back to a spot in the middle of the Dock if the app has no icon there.
    /// Runs Accessibility calls: never call it from the main thread.
    static func frame(forApp pid: pid_t) -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let list = children(of: app).first(where: { role(of: $0) == kAXListRole as String }) else { return nil }

        let target = NSRunningApplication(processIdentifier: pid)
        for item in children(of: list) {
            // The item's frame also covers the room around the icon: the icon is the square at its top-left.
            if matches(item, target), let frame = AXBridge.frame(of: item), frame.width > 1 {
                let side = min(frame.width, frame.height)
                return CGRect(x: frame.minX, y: frame.minY, width: side, height: side)
            }
        }
        guard let dockFrame = AXBridge.frame(of: list) else { return nil }
        return CGRect(x: dockFrame.midX - iconSize / 2, y: dockFrame.midY - iconSize / 2, width: iconSize, height: iconSize)
    }

    private static func matches(_ item: AXUIElement, _ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        var url: CFTypeRef?
        if AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &url) == .success,
           let itemURL = url as? URL, let bundleURL = app.bundleURL {
            return itemURL.standardizedFileURL.path == bundleURL.standardizedFileURL.path
        }
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title) == .success, let name = title as? String {
            return name == app.localizedName
        }
        return false
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
