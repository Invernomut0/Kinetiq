// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import Darwin
import KinetiqCore
import Metal
import QuartzCore
import XCTest
@testable import Kinetiq

/// Real README-backed AppKit windows in a disposable child. No event taps,
/// posted input, user-window captures, normal product lifecycle or consent changes.
final class WobblyWindowCompatibilityTests: XCTestCase {
    private struct Helper {
        let process: Process
        let id: CGWindowID
        let parentID: CGWindowID
        let frame: CGRect
        let safeTitle: CGPoint
        let button: CGPoint?
        let field: CGPoint?
        let nativeControls: [CGPoint]
        let titleHeight: CGFloat
        let level: Int

        var info: WindowInfo { WindowInfo(id: id, pid: process.processIdentifier, frame: frame, layer: level) }
        var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
        var diagnostic: String {
            "child PID=\(process.processIdentifier), ID=\(id), parent=\(parentID), level=\(level), expected=\(frame), actual=\(String(describing: WindowLocator.snapshot(of: id)))"
        }
    }

    @MainActor private func prerequisites(metal: Bool = false) throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty, CGSessionCopyCurrentDictionary() != nil else {
            throw XCTSkip("A graphical WindowServer session is required")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording permission required; no prompt")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility permission required; no prompt")
        }
        if metal, MTLCreateSystemDefaultDevice() == nil { throw XCTSkip("Metal unavailable") }
    }

    /// Poll only observable readiness with an explicit deadline, yielding the main actor.
    @MainActor private func waitUntil(seconds: Double = 4,
                                     _ ready: () async -> Bool) async throws -> Bool {
        let deadline = CACurrentMediaTime() + seconds
        repeat {
            if await ready() { return true }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        return false
    }

    /// Every test-owned AX query is serialized on the helper's queue.
    private func ax<T>(_ pid: pid_t, _ query: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            AXBridge.queue(for: pid).async { continuation.resume(returning: query()) }
        }
    }

    @MainActor private func helper(_ kind: String) async throws -> Helper {
        try prerequisites()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let readme = root.appendingPathComponent("README.md")
        XCTAssertFalse(try String(contentsOf: readme, encoding: .utf8).isEmpty)
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-e", Self.helperProgram, readme.path, kind]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        // Do not override environment, read configuration, or launch a product app.
        try process.run()
        addTeardownBlock {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            await Task.detached { process.waitUntilExit() }.value
            try? output.fileHandleForReading.close()
        }

        // Nonblocking, bounded metadata: availableData could hang forever if swift
        // fails before publishing. Compilation gets its own 30-second deadline.
        let fd = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw NSError(domain: "WobblyHelperPipe", code: Int(errno))
        }
        var metadata = Data()
        let received = try await waitUntil(seconds: 30) {
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 { metadata.append(contentsOf: bytes.prefix(count)) }
            return metadata.contains(10) || metadata.count > 65_536 || !process.isRunning
        }
        XCTAssertTrue(received, "Child metadata deadline; PID=\(process.processIdentifier), kind=\(kind)")
        XCTAssertLessThanOrEqual(metadata.count, 65_536)
        guard received, metadata.count <= 65_536, let newline = metadata.firstIndex(of: 10) else {
            throw NSError(domain: "WobblyHelperMetadata", code: 1)
        }
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: metadata[..<newline]) as? [String: Any])
        func point(_ value: Any?) throws -> CGPoint {
            let values = try XCTUnwrap(value as? [Double])
            XCTAssertEqual(values.count, 2)
            guard values.count == 2, values.allSatisfy(\.isFinite) else {
                throw NSError(domain: "WobblyHelperPoint", code: 1)
            }
            return CGPoint(x: values[0], y: values[1])
        }
        let values = try XCTUnwrap(object["frame"] as? [Double])
        XCTAssertEqual(values.count, 4)
        guard values.count == 4, values.allSatisfy(\.isFinite) else {
            throw NSError(domain: "WobblyHelperFrame", code: 1)
        }
        XCTAssertEqual(try XCTUnwrap(object["pid"] as? Int), Int(process.processIdentifier))
        let child = Helper(process: process,
            id: try XCTUnwrap((object["id"] as? NSNumber)?.uint32Value),
            parentID: try XCTUnwrap((object["parent"] as? NSNumber)?.uint32Value),
            frame: CGRect(x: values[0], y: values[1], width: values[2], height: values[3]),
            safeTitle: try point(object["safe"]),
            button: try object["button"].map(point), field: try object["field"].map(point),
            nativeControls: try (object["native"] as? [[Double]] ?? []).map { try point($0) },
            titleHeight: try XCTUnwrap(object["height"] as? Double),
            level: try XCTUnwrap(object["level"] as? Int))
        XCTAssertNotEqual(child.id, 0)
        XCTAssertNotEqual(child.info.pid, ProcessInfo.processInfo.processIdentifier)
        let settled = try await waitUntil {
            guard process.isRunning, let snapshot = WindowLocator.snapshot(of: child.id),
                  snapshot.alpha > 0.97, snapshot.frame == child.frame else { return false }
            // The production selector ignores known click-through recorder/cursor
            // overlays. Raw WindowServer ordering alone incorrectly blocks readiness.
            let selected = WindowLocator.dragWindow(at: child.center)
            return selected?.id == child.id && selected?.pid == process.processIdentifier
        }
        XCTAssertTrue(settled, child.diagnostic)
        guard settled else { throw NSError(domain: "WobblyHelperReadiness", code: 1) }
        return child
    }

    @MainActor private func resolved(_ child: Helper, at point: CGPoint) async throws -> AXUIElement {
        var result: AXUIElement?
        let ready = try await waitUntil {
            result = await self.ax(child.info.pid) { AXBridge.findMovableWindow(child.info, hitPoint: point) }
            return result != nil
        }
        XCTAssertTrue(ready, "Movable AX resolution: \(child.diagnostic)")
        let window = try XCTUnwrap(result, child.diagnostic)
        let identity = await ax(child.info.pid) { () -> (CGWindowID?, pid_t, CGRect?, Bool, Bool) in
            var pid: pid_t = 0
            XCTAssertEqual(AXUIElementGetPid(window, &pid), .success)
            var writable = DarwinBoolean(false)
            XCTAssertEqual(AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &writable), .success)
            return (AXBridge.windowID(of: window), pid, AXBridge.frame(of: window), writable.boolValue,
                    AXBridge.isFullScreen(window))
        }
        XCTAssertEqual(identity.0, child.id)
        XCTAssertEqual(identity.1, child.info.pid)
        XCTAssertEqual(identity.2, child.frame)
        XCTAssertTrue(identity.3, child.diagnostic)
        XCTAssertFalse(identity.4)
        return window
    }

    @MainActor func testStandardWindowSelectionAndNativeControlsRemainSafe() async throws {
        let child = try await helper("standard")
        XCTAssertEqual(child.level, NSWindow.Level.normal.rawValue)
        let selected = try XCTUnwrap(WindowLocator.dragWindow(at: child.center), child.diagnostic)
        XCTAssertEqual(selected.id, child.id); XCTAssertEqual(selected.pid, child.info.pid)
        XCTAssertEqual(WindowLocator.window(at: child.center)?.id, child.id)
        _ = try await resolved(child, at: child.center)
        try await assertTitleAndControls(child)
    }

    @MainActor func testFloatingModalAndPopUpPanelsDoNotRelaxOrdinaryLocator() async throws {
        for kind in ["floating", "modal", "popup"] {
            let child = try await helper(kind)
            XCTAssertNotEqual(child.id, child.parentID)
            XCTAssertNotEqual(child.level, NSWindow.Level.normal.rawValue)
            let selected = try XCTUnwrap(WindowLocator.dragWindow(at: child.center), child.diagnostic)
            XCTAssertEqual(selected.id, child.id); XCTAssertEqual(selected.pid, child.info.pid)
            XCTAssertEqual(selected.frame, child.frame)
            XCTAssertNil(WindowLocator.window(at: child.center), "Ordinary effects must not select the underlying parent")
            _ = try await resolved(child, at: child.center)
            let invalid = WindowInfo(id: .max, pid: child.info.pid, frame: child.frame)
            let guessed = await ax(child.info.pid) { AXBridge.findMovableWindow(invalid, hitPoint: child.center) }
            XCTAssertNil(guessed, "Neither hit-test nor same-frame fallback may resolve an invalid ID to the panel/parent")
            try await assertTitleAndControls(child)
            // End each owned child before another level changes the frontmost result.
            if child.process.isRunning { child.process.terminate() }
            await Task.detached { child.process.waitUntilExit() }.value
        }
    }

    @MainActor private func assertTitleAndControls(_ child: Helper) async throws {
        let height = await ax(child.info.pid) { AXBridge.titleBarHeight(child.info, at: child.safeTitle) }
        XCTAssertGreaterThan(try XCTUnwrap(height, child.diagnostic), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(height), 120)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(height), child.safeTitle.y - child.frame.minY)
        XCTAssertGreaterThan(child.titleHeight, 0)
        let button = try XCTUnwrap(child.button, "Actual NSButton geometry is required")
        let field = try XCTUnwrap(child.field, "Actual editable NSTextField geometry is required")
        let controls = child.nativeControls.map { ($0, kAXButtonRole as String) }
            + [(button, kAXButtonRole as String), (field, kAXTextFieldRole as String)]
        for (point, expectedRole) in controls {
            let hit = await ax(child.info.pid) { () -> (Set<String>, CGWindowID?, pid_t) in
                let app = AXUIElementCreateApplication(child.info.pid)
                AXUIElementSetMessagingTimeout(app, 0.25)
                var current: AXUIElement?
                guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &current) == .success else {
                    return ([], nil, 0)
                }
                var roles: Set<String> = [], pid: pid_t = 0
                if let current { AXUIElementGetPid(current, &pid) }
                for _ in 0..<8 {
                    guard let node = current else { break }
                    AXUIElementSetMessagingTimeout(node, 0.25)
                    var role: CFTypeRef?
                    AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role)
                    if let name = role as? String {
                        roles.insert(name)
                        if name == kAXWindowRole as String { return (roles, AXBridge.windowID(of: node), pid) }
                    }
                    var parent: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent) == .success,
                          let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                    current = (parent as! AXUIElement)
                }
                return (roles, nil, pid)
            }
            XCTAssertTrue(hit.0.contains(expectedRole), "Point must really hit \(expectedRole), not empty chrome: \(hit.0); \(child.diagnostic)")
            XCTAssertEqual(hit.1, child.id)
            XCTAssertEqual(hit.2, child.info.pid)
            let blocked = await ax(child.info.pid) { AXBridge.titleBarHeight(child.info, at: point) }
            XCTAssertNil(blocked, "Real native/button/text-field control must not become a draggable title strip: \(point); \(child.diagnostic)")
        }
        XCTAssertEqual(WindowLocator.frame(of: child.id), child.frame)
    }

    @MainActor func testTitleStripWithoutCloseButtonAndBorderlessMovablePanel() async throws {
        let titled = try await helper("noClose")
        XCTAssertTrue(titled.nativeControls.isEmpty, "The helper really has no traffic-light buttons")
        let window = try await resolved(titled, at: titled.safeTitle)
        let hasClose = await ax(titled.info.pid) { () -> Bool in
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success
                && value.map { CFGetTypeID($0) == AXUIElementGetTypeID() } == true
        }
        XCTAssertFalse(hasClose, "The real AX window, not just its style metadata, must lack a close button")
        try await assertTitleAndControls(titled)
        if titled.process.isRunning { titled.process.terminate() }
        await Task.detached { titled.process.waitUntilExit() }.value
        let borderless = try await helper("borderless")
        XCTAssertEqual(borderless.titleHeight, 0)
        XCTAssertEqual(WindowLocator.dragWindow(at: borderless.center)?.id, borderless.id)
        XCTAssertNil(WindowLocator.window(at: borderless.center))
        _ = try await resolved(borderless, at: borderless.center)
        let height = await ax(borderless.info.pid) { AXBridge.titleBarHeight(borderless.info, at: borderless.center) }
        XCTAssertNil(height, "Borderless contents are not an inferred title bar")
    }

    @MainActor func testRealSeventyByThirtyFivePanelIsEligibleOnlyForDrag() async throws {
        let child = try await helper("tiny")
        XCTAssertEqual(child.frame.size, CGSize(width: 70, height: 35))
        let selected = try XCTUnwrap(WindowLocator.dragWindow(at: child.center), child.diagnostic)
        XCTAssertEqual(selected.id, child.id); XCTAssertEqual(selected.pid, child.info.pid)
        XCTAssertNil(WindowLocator.window(at: child.center))
        _ = try await resolved(child, at: child.center)
    }

    @MainActor func testOwnProcessWindowIsNeverADragTargetOrMoved() async throws {
        try prerequisites()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let window = NSWindow(contentRect: screen.visibleFrame.insetBy(dx: screen.visibleFrame.width / 3,
                              dy: screen.visibleFrame.height / 3), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        defer { window.close() }
        window.orderFrontRegardless(); window.displayIfNeeded()
        let id = CGWindowID(window.windowNumber), original = window.frame
        let ready = try await waitUntil {
            guard let snapshot = WindowLocator.snapshot(of: id), snapshot.alpha > 0.97 else { return false }
            let point = CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            let first = entries.first {
                guard ($0[kCGWindowLayer as String] as? Int ?? 0) == 0,
                      ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                      let bounds = $0[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
                return frame.contains(point)
            }
            return (first?[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id
        }
        XCTAssertTrue(ready)
        let frame = try XCTUnwrap(WindowLocator.frame(of: id))
        let point = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertNil(WindowLocator.dragWindow(at: point))
        XCTAssertNil(WindowLocator.window(at: point))
        XCTAssertEqual(window.frame, original)
        // Deliberately no controller, AX access or move for a self-process window.
    }

    @MainActor private func controller(_ child: Helper) throws -> KinetiqController {
        let suite = "io.github.invernomut0.Kinetiq.wobbly-compatibility-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        settings.enabled = true; settings.titleBarDrag = true; settings.modifier = .controlCommand
        settings.closeEffect = .off; settings.openEffect = .off; settings.minimizeEffect = .off
        settings.maximizeEffect = false; settings.resizeEffect = false
        settings.glideOnFlick = false; settings.focusPulse = false
        settings.rippleOnDrop = false; settings.tiltOnDrag = false
        return try XCTUnwrap(KinetiqController(settings: settings,
            windowFilter: { $0.pid == child.info.pid && $0.id == child.id }, dragPreset: { nil }))
    }

    @MainActor private func event(_ type: CGEventType, at point: CGPoint, plain: Bool) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                         mouseCursorPosition: point, mouseButton: .left))
        event.flags = plain ? [] : DragModifier.controlCommand.flags
        return event // Never post or replay these events.
    }

    @MainActor private func dragAndCancel(_ child: Helper, plain: Bool) async throws {
        try prerequisites(metal: true)
        let point = plain ? child.safeTitle : child.center
        let element = try await resolved(child, at: point)
        let parentFrame = child.parentID == child.id ? nil : try XCTUnwrap(WindowLocator.frame(of: child.parentID))
        let controller = try controller(child)
        defer { controller.cancelAll() }
        XCTAssertNil(controller.animatedWindowID); XCTAssertFalse(controller.isDragWindowParked)
        let acceptedDown = controller.handle(.leftMouseDown, try event(.leftMouseDown, at: point, plain: plain))
        XCTAssertTrue(acceptedDown, child.diagnostic)
        guard acceptedDown else { throw NSError(domain: "WobblyDragAdmission", code: 1) }
        // A plain held click must transition to a real drag before mouse-up;
        // otherwise the product legitimately replays a native click globally.
        let moved = CGPoint(x: point.x + 32, y: point.y + 18)
        let acceptedDrag = controller.handle(.leftMouseDragged, try event(.leftMouseDragged, at: moved, plain: plain))
        XCTAssertTrue(acceptedDrag)
        guard acceptedDrag else { throw NSError(domain: "WobblyDragAdmission", code: 2) }
        let parked = try await waitUntil(seconds: 8) {
            guard controller.animatedWindowID == child.id, controller.isDragWindowParked else { return false }
            let actual = await self.ax(child.info.pid) { AXBridge.frame(of: element) }
            return actual.map { frame in
                let visibleArea = NSScreen.screens.reduce(CGFloat.zero) { total, screen in
                    let overlap = screen.cgFrame.intersection(frame)
                    return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
                }
                // AppKit can clamp Y to keep a title bar accessible while X is
                // parked at the edge. Require <=2 exposed pixel columns/rows.
                return frame.origin != child.frame.origin && frame.size == child.frame.size
                    && visibleArea <= 2 * max(frame.width, frame.height)
            } ?? false
        }
        XCTAssertTrue(parked, "Actual capture/Metal/deformer and AX parking required; animated=\(String(describing: controller.animatedWindowID)), parked=\(controller.isDragWindowParked); \(child.diagnostic)")
        XCTAssertEqual(controller.animatedWindowID, child.id)
        XCTAssertTrue(controller.isDragWindowParked)
        if let parentFrame { XCTAssertEqual(WindowLocator.frame(of: child.parentID), parentFrame, "Only the selected panel may be parked") }
        // Cancel restores the last rigid drag origin, not necessarily mouse-down.
        // Return to the initial pointer so exact original CGRect is the contract.
        XCTAssertTrue(controller.handle(.leftMouseDragged, try event(.leftMouseDragged, at: point, plain: plain)))
        XCTAssertTrue(controller.handle(.leftMouseUp, try event(.leftMouseUp, at: point, plain: plain)))
        controller.cancelAll()
        XCTAssertNil(controller.animatedWindowID); XCTAssertFalse(controller.isDragWindowParked)
        let restored = try await waitUntil {
            let actual = await self.ax(child.info.pid) { AXBridge.frame(of: element) }
            return actual == child.frame && WindowLocator.frame(of: child.id) == child.frame
        }
        XCTAssertTrue(restored, "Cancellation must restore exact origin and size: \(child.diagnostic)")
        let actual = await ax(child.info.pid) { AXBridge.frame(of: element) }
        XCTAssertEqual(actual, child.frame)
        XCTAssertEqual(WindowLocator.frame(of: child.id), child.frame)
        controller.cancelAll() // Idempotent and never leaves an owned window parked.
        XCTAssertEqual(WindowLocator.frame(of: child.id), child.frame)
        if let parentFrame { XCTAssertEqual(WindowLocator.frame(of: child.parentID), parentFrame) }
    }

    @MainActor func testModifierDragCapturesDeformsParksAndCancellationRestoresFloatingPanel() async throws {
        let child = try await helper("floating")
        try await dragAndCancel(child, plain: false)
    }

    @MainActor func testPlainTitleDragWithoutCloseButtonCapturesAndRestoresExactOrigin() async throws {
        let child = try await helper("noClose")
        try await dragAndCancel(child, plain: true)
    }

    /// Metadata contains only this process's actual native windows/control geometry.
    /// The stdin reader and 90-second watchdog bound lifetime even after test failure.
    private static let helperProgram = #"""
    import AppKit
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    let screen = NSScreen.screens.first!
    let visible = screen.visibleFrame
    let kind = CommandLine.arguments[2]
    let readme = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    precondition(!readme.isEmpty)
    let tiny = kind == "tiny"
    let borderless = tiny || kind == "borderless"
    let panel = ["floating", "modal", "popup", "borderless", "tiny"].contains(kind)
    var style: NSWindow.StyleMask = borderless ? [.borderless] : [.titled]
    if !borderless && kind != "noClose" { style.formUnion([.closable, .miniaturizable, .resizable]) }
    let rect = NSRect(x: visible.minX + 90, y: visible.minY + 110,
                      width: tiny ? 70 : 440, height: tiny ? 35 : 260)
    let window: NSWindow = panel
        ? NSPanel(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        : NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.isMovable = true
    window.isMovableByWindowBackground = borderless
    window.title = "Wobbly compatibility — README.md"
    if !borderless {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
    if let p = window as? NSPanel {
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.isFloatingPanel = true
        p.level = kind == "popup" ? .popUpMenu : kind == "modal" ? .modalPanel : .floating
    }
    let content = NSView(frame: window.contentView!.bounds)
    content.autoresizingMask = [.width, .height]
    let text = NSTextView(frame: content.bounds.insetBy(dx: tiny ? 0 : 12, dy: tiny ? 0 : 32))
    text.autoresizingMask = [.width, .height]
    text.string = readme
    text.isEditable = false
    text.isSelectable = false
    text.drawsBackground = true
    text.font = .monospacedSystemFont(ofSize: tiny ? 8 : 12, weight: .regular)
    content.addSubview(text)
    var button: NSButton?
    var field: NSTextField?
    if !borderless {
        // Actual interactive controls immediately below the native title strip.
        let b = NSButton(frame: NSRect(x: content.bounds.maxX - 76, y: content.bounds.maxY - 22, width: 68, height: 20))
        b.title = "README"
        b.bezelStyle = .rounded
        b.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(b); button = b
        let f = NSTextField(frame: NSRect(x: content.bounds.maxX - 170, y: content.bounds.maxY - 22, width: 88, height: 20))
        f.stringValue = "README.md"
        f.isEditable = true
        f.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(f); field = f
    }
    window.contentView = content
    var parent: NSWindow?
    if panel {
        let p = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false; p.animationBehavior = .none
        p.title = "README parent — never move"
        let text = NSTextView(frame: p.contentView!.bounds)
        text.string = readme; text.isEditable = false
        p.contentView = text
        p.setFrame(window.frame, display: true)
        p.orderFrontRegardless()
        p.addChildWindow(window, ordered: .above)
        parent = p
    }
    let reader = Thread {
        while readLine() != nil {}
        DispatchQueue.main.async { exit(0) }
    }
    reader.start()
    DispatchQueue.main.async {
        app.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // addChildWindow/activation can inherit the parent's normal level. Set
        // the actual requested test level after those native operations.
        if panel { window.level = kind == "popup" ? .popUpMenu : kind == "modal" ? .modalPanel : .floating }
        window.orderFrontRegardless()
        window.displayIfNeeded()
        let top = NSScreen.screens.first!.frame.maxY
        func cg(_ point: NSPoint) -> [Double] { [point.x, top - point.y] }
        func center(_ view: NSView) -> [Double] {
            cg(window.convertPoint(toScreen: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)))
        }
        let frame = window.frame
        let native = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }.filter { !$0.isHidden }.map(center)
        var metadata: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "id": window.windowNumber, "parent": parent?.windowNumber ?? window.windowNumber,
            "frame": [frame.minX, top - frame.maxY, frame.width, frame.height],
            "safe": [frame.minX + frame.width * 0.35, top - frame.maxY + 11],
            "native": native, "height": frame.height - window.contentLayoutRect.height,
            "level": window.level.rawValue
        ]
        if let button { metadata["button"] = center(button) }
        if let field { metadata["field"] = center(field) }
        var data = try! JSONSerialization.data(withJSONObject: metadata)
        data.append(10)
        FileHandle.standardOutput.write(data)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { exit(0) }
    app.run()
    """#
}