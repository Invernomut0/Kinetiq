// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import QuartzCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Access to other apps' windows through the public Accessibility API.
/// Every call is IPC with the owning app, so they run on that app's `queue` and never on the main thread.
enum AXBridge {
    private static let queuesLock = NSLock()
    private static var queues: [pid_t: DispatchQueue] = [:]

    /// For moves that must not wait behind the app's other Accessibility calls (a slow one can take hundreds of ms).
    static let urgentQueue = DispatchQueue(label: "kinetiq.ax.urgent", qos: .userInteractive, attributes: .concurrent)

    /// One serial queue per app: calls to the same app keep their order, but a slow app
    /// can't hold up the window the user has just grabbed in another one.
    static func queue(for pid: pid_t) -> DispatchQueue {
        queuesLock.lock()
        defer { queuesLock.unlock() }
        if let queue = queues[pid] { return queue }
        let queue = DispatchQueue(label: "kinetiq.ax.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        return queue
    }

    static func queue(for element: AXUIElement) -> DispatchQueue {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return queue(for: pid)
    }

    static func findWindow(_ info: WindowInfo, hitPoint: CGPoint, timeout: Float = 0.25,
                           requireIdentity: Bool = false) -> AXUIElement? {
        let deadline = CACurrentMediaTime() + Double(timeout)
        func bounded(_ window: AXUIElement) -> AXUIElement? {
            let remaining = deadline - CACurrentMediaTime()
            guard remaining > 0 else { return nil }
            return limit(window, min(0.025, Float(remaining)))
        }
        let app = AXUIElementCreateApplication(info.pid)
        AXUIElementSetMessagingTimeout(app, timeout)

        var value: CFTypeRef?
        let windows = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success
            ? value as? [AXUIElement] ?? [] : []
        // Exact match: identical frames are common (maximized or tiled windows of the same app on other Spaces).
        for candidate in windows {
            guard let window = bounded(candidate) else { return nil }
            if windowID(of: window) == info.id { return limit(window, 0) }
        }

        // Fallback: what the app says is under the cursor can only be on the current Space.
        let remaining = deadline - CACurrentMediaTime()
        guard remaining > 0 else { return nil }
        if let hit = hitTest(info.pid, at: hitPoint, timeout: min(0.025, Float(remaining))).flatMap(bounded),
           let candidate = role(of: hit) == kAXWindowRole as String ? hit : element(hit, kAXWindowAttribute),
           let window = bounded(candidate), matchesWindow(window, info: info),
           !requireIdentity || windowID(of: window) == info.id {
            return limit(window, 0)
        }
        guard !requireIdentity else { return nil }

        // Last resort: frame match, but only if unambiguous. Guessing would park the wrong window.
        var candidates: [AXUIElement] = []
        for candidate in windows {
            guard let window = bounded(candidate) else { return nil }
            if matchesWindow(window, info: info), frame(of: window).map({ matches($0, info.frame) }) == true {
                candidates.append(window)
            }
        }
        return candidates.count == 1 ? limit(candidates[0], 0) : nil
    }

    /// Never substitute a popup's parent (even if both have the same frame).
    private static func matchesWindow(_ window: AXUIElement, info: WindowInfo) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid == info.pid else { return false }
        if let id = windowID(of: window) { return id == info.id }
        return frame(of: window).map { matches($0, info.frame) } ?? false
    }

    /// Drag capability, not AXStandardWindow: panels and custom app windows may move too.
    static func findMovableWindow(_ info: WindowInfo, hitPoint: CGPoint) -> AXUIElement? {
        enableChromiumAccessibility(pid: info.pid)
        guard let window = findWindow(info, hitPoint: hitPoint, timeout: 0.1, requireIdentity: true) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.025)
        var writable = DarwinBoolean(false)
        guard role(of: window) == kAXWindowRole as String, !isFullScreen(window),
              AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &writable) == .success,
              writable.boolValue else { return nil }
                // Queries are bounded; moving a slow app must retain its normal IPC timeout.
                AXUIElementSetMessagingTimeout(window, 0)
        return window
    }

    /// CGWindowID behind an AX window (private, but stable for years and used by yabai, AeroSpace, AltTab…).
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success ? id : nil
    }

    /// The window of `pid` that has keyboard focus (the one ⌘W would close).
    static func focusedWindow(pid: pid_t) -> WindowInfo? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = element(app, kAXFocusedWindowAttribute), let id = windowID(of: window),
              let frame = frame(of: window) else { return nil }
        return WindowInfo(id: id, pid: pid, frame: frame)
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    private static let draggableRoles: Set<String> = [
        kAXWindowRole as String, kAXToolbarRole as String, kAXGroupRole as String, kAXStaticTextRole as String,
        kAXImageRole as String, "AXSplitGroup", "AXLayoutArea", "AXUnknown",
    ]

    /// If `point` falls on a draggable area of the title bar (not a button, tab or field), returns the
    /// height of that bar. It is inferred from the close button, which macOS centers vertically in it;
    /// Missing/nonstandard close buttons use only a narrow empty title strip;
    /// buttons, fields, tabs and other interactive descendants stay native.
    /// Called from the event tap, so it uses a short timeout.
    static func titleBarHeight(_ info: WindowInfo, at point: CGPoint) -> CGFloat? {
        // Asking our own process through Accessibility from the event tap (main thread) would only time out.
        if info.pid == ProcessInfo.processInfo.processIdentifier {
            return MainActor.assumeIsolated { ownTitleBarHeight(info, at: point) }
        }
        enableChromiumAccessibility(pid: info.pid)
        guard let hit = hitTest(info.pid, at: point, timeout: 0.1).map({ limit($0, 0.1) }),
              draggableWindow(from: hit) != nil else { return nil }
                // Chromium can hang its title strip from a pseudo-window. Resolve the
                // actual WindowServer target, never fall back to a different parent.
        guard let window = findMovableWindow(info, hitPoint: point).map({ limit($0, 0.1) }) else { return nil }
                guard let close = element(window, kAXCloseButtonAttribute).map({ limit($0, 0.1) }),
              let closeFrame = frame(of: close) else {
            return emptyTitleStripHeight(window, hit: hit, info: info, point: point)
                }

        let closeCenter = CGPoint(x: closeFrame.midX, y: closeFrame.midY)
        guard info.frame.contains(closeCenter) else {
            // iTerm2 (Minimal theme) reports its close button outside the window. Without it the bar height is
            // unknown: take the standard one, and only for the empty bar (a tab title is an `AXStaticText`).
            return emptyTitleStripHeight(window, hit: hit, info: info, point: point)
        }

        let height = 2 * (closeCenter.y - info.frame.minY)
        guard height >= 20, height <= 120 else {
            return emptyTitleStripHeight(window, hit: hit, info: info, point: point)
        }
        guard point.y - info.frame.minY <= height else { return nil }
        return height
    }

    private static let unknownTitleBarHeight: CGFloat = 28

    private static func emptyTitleStripHeight(_ window: AXUIElement, hit: AXUIElement,
                                             info: WindowInfo, point: CGPoint) -> CGFloat? {
        guard info.frame.contains(point), point.y - info.frame.minY <= unknownTitleBarHeight else { return nil }
        let emptyRoles: Set<String> = [kAXWindowRole as String, kAXToolbarRole as String,
                                      kAXGroupRole as String, "AXUnknown"]
        let isTitle = element(window, "AXTitleUIElement").map { CFEqual($0, hit) } ?? false
        guard role(of: hit).map(emptyRoles.contains) == true || isTitle else { return nil }
        return min(unknownTitleBarHeight, info.frame.height)
    }

    @MainActor
    private static func ownTitleBarHeight(_ info: WindowInfo, at point: CGPoint) -> CGFloat? {
        guard let window = NSApp.window(withWindowNumber: Int(info.id)) else { return nil }
        let height = window.frame.height - window.contentLayoutRect.height
        guard height >= 20, point.y - info.frame.minY <= height else { return nil }
        return height
    }

    private static var manualAccessibilityPIDs: Set<pid_t> = []

    /// Chromium and Electron apps expose an incomplete tree (windows with no close button, missing groups) until
    /// a client asks for it. Other apps ignore the attribute. Done once per app.
    static func enableChromiumAccessibility(pid: pid_t) {
        queuesLock.lock()
        let isNew = manualAccessibilityPIDs.insert(pid).inserted
        queuesLock.unlock()
        guard isNew else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Walks up from `hit` to its window and returns it only if every element on the way is draggable.
    /// The hit test returns the deepest element, which is often plain text or a group inside a control:
    /// the title of a Chromium tab is an `AXStaticText` whose parent is the tab itself (`AXRadioButton`).
    private static func draggableWindow(from hit: AXUIElement) -> AXUIElement? {
        var current = hit
        let deadline = CACurrentMediaTime() + 0.1
        for _ in 0..<32 {
            let remaining = deadline - CACurrentMediaTime()
            guard remaining > 0 else { return nil }
            current = limit(current, min(0.025, Float(remaining)))
            guard let role = role(of: current), draggableRoles.contains(role) else { return nil }
            if role == kAXWindowRole as String { return current }
            guard let parent = element(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    /// Asks the owning app rather than the system-wide element, so transparent layers from other apps
    /// (screen recorders, for example) don't get in the way. `WindowLocator` has already checked that
    /// the window is frontmost.
    private static func hitTest(_ pid: pid_t, at point: CGPoint, timeout: Float) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        return hit
    }

    /// Elements obtained from another one don't inherit its messaging timeout: without this, a busy app
    /// could block the event tap for the system default of several seconds. Only for queries: windows
    /// that will be moved keep the default so a slow app still gets the move.
    private static func limit(_ element: AXUIElement, _ timeout: Float) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute), let size = size(window) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Regular document-style windows only: no sheets, popovers, panels or tooltips.
    static func isStandardWindow(_ window: AXUIElement) -> Bool {
        subrole(of: window) == kAXStandardWindowSubrole as String
    }

    /// Frame of the yellow minimize button if that is what lies under `point` (or inside it, for a window's contents).
    /// Called from the event tap, so it uses short timeouts.
    static func minimizeButtonFrame(pid: pid_t, at point: CGPoint) -> CGRect? {
        guard let hit = hitTest(pid, at: point, timeout: 0.1) else { return nil }
        var current = limit(hit, 0.1)
        for _ in 0..<2 {
            if subrole(of: current) == kAXMinimizeButtonSubrole as String { return frame(of: current) }
            guard let parent = element(current, kAXParentAttribute) else { return nil }
            current = limit(parent, 0.1)
        }
        return nil
    }

    static func setMinimized(_ window: AXUIElement, _ minimized: Bool) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private static func subrole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func raise(_ window: AXUIElement, pid: pid_t) {
        // Make it the app's main window first, so activating the app doesn't jump to a Space with another of its windows.
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}

/// Moves a window along with the mouse, keeping only the latest requested position
/// so dozens of AX calls don't pile up if the app is slow to respond.
final class CoalescingMover {
    private let lock = NSLock()
    private var pending: (AXUIElement, CGPoint)?
    private var scheduled = false

    func move(_ window: AXUIElement, to point: CGPoint) {
        lock.lock()
        pending = (window, point)
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needsSchedule else { return }

        AXBridge.queue(for: window).async { [self] in
            lock.lock()
            let job = pending
            pending = nil
            scheduled = false
            lock.unlock()
            if let (window, point) = job { AXBridge.setPosition(window, point) }
        }
    }
}
