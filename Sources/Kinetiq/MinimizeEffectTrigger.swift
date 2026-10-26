// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import QuartzCore

/// Plays an effect when a window is minimized with its yellow button.
///
/// macOS animates a minimize on its own, so the click is held back. If it ends on the button and the window has been
/// captured, the window is parked off-screen, minimized there (the system animation has nothing to show) and the
/// effect plays over where the window was; the minimized window is then put back at its position, so it comes back
/// where it was. In every other case (no capture, the pointer left the button) the click is replayed untouched.
/// Only the yellow button is handled: ⌘M and the Dock cannot be intercepted without reading keystrokes.
@MainActor
final class MinimizeEffectTrigger {
    private struct Pending {
        let info: WindowInfo
        let buttonFrame: CGRect
        let down: CGEvent
        let capture: Task<CapturedFrame?, Never>
        let startedAt: CFTimeInterval
    }

    /// Area of a window, from its top-left corner, where the window buttons are.
    private static let buttonArea = CGSize(width: 110, height: 52)
    /// A capture that takes longer than this after the click is not worth waiting for: the click is replayed.
    private static let captureTimeout: CFTimeInterval = 0.5
    /// Frames the overlay shows the window before the real one is parked, as in a drag.
    private static let parkDelay: TimeInterval = 0.04
    private static let failsafe: TimeInterval = 15

    private let settings: Settings
    private let capture: WindowCapture
    private let player: CloseEffectPlayer
    private let isBusy: () -> Bool
    private let replay: (CGEvent, CGEvent) -> Void
    private var pending: Pending?

    init(settings: Settings, capture: WindowCapture, player: CloseEffectPlayer, isBusy: @escaping () -> Bool,
         replay: @escaping (CGEvent, CGEvent) -> Void) {
        self.settings = settings
        self.capture = capture
        self.player = player
        self.isBusy = isBusy
        self.replay = replay
    }

    /// A click on the button is being held back.
    var isPending: Bool { pending != nil }

    func cancel() {
        pending = nil
    }

    /// Returns true if the click is held back.
    func mouseDown(_ event: CGEvent, windows: WindowList) -> Bool {
        let point = event.location
        guard settings.enabled, settings.minimizeEffect != .off, pending == nil, !isBusy(),
              let info = WindowLocator.window(at: point, in: windows) else { return false }
        let local = CGPoint(x: point.x - info.frame.minX, y: point.y - info.frame.minY)
        guard local.x >= 0, local.y >= 0, local.x <= Self.buttonArea.width, local.y <= Self.buttonArea.height,
              let button = AXBridge.minimizeButtonFrame(pid: info.pid, at: point), let down = event.copy() else { return false }
        // The capture starts with the click: it is what takes longest.
        let task = Task { try? await capture.capture(info) }
        pending = Pending(info: info, buttonFrame: button, down: down, capture: task, startedAt: CACurrentMediaTime())
        return true
    }

    /// Always consumes the event: the pair is either replayed or turned into a minimize with an effect.
    func mouseUp(_ event: CGEvent) -> Bool {
        guard let click = pending, let up = event.copy() else { return false }
        pending = nil
        guard click.buttonFrame.contains(event.location) else {
            replay(click.down, up)
            return true
        }
        Task { await minimize(click, up: up) }
        return true
    }

    private func minimize(_ click: Pending, up: CGEvent) async {
        let info = click.info
        let frame = await click.capture.value
        guard let frame, frame.isPainted, frame.pointSize == info.frame.size,
              CACurrentMediaTime() - click.startedAt < Self.captureTimeout, !isBusy(),
              let effect = player.effect(for: settings.minimizeEffect) else {
            replay(click.down, up)
            return
        }
        let element: AXUIElement? = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async {
                continuation.resume(returning: AXBridge.findWindow(info, hitPoint: click.buttonFrame.origin))
            }
        }
        guard let element else {
            replay(click.down, up)
            return
        }

        var restored = false
        let restore: () -> Void = {
            guard !restored else { return }
            restored = true
            AXBridge.queue(for: element).async { AXBridge.setPosition(element, info.frame.origin) }
        }
        let started = player.play(
            frame, windowFrame: info.frame, effect: effect, pointer: CGPoint(x: click.buttonFrame.midX, y: click.buttonFrame.midY),
            durationScale: settings.closeDuration, nativeFade: true, nearEnd: restore)
        guard started else {
            replay(click.down, up)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.failsafe) { restore() }

        // Parked and minimized in one go, so the system animation starts from a window that is not on screen.
        let park = NSScreen.parkingPoint
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.parkDelay) {
            AXBridge.queue(for: element).async {
                AXBridge.setPosition(element, park)
                AXBridge.setMinimized(element, true)
            }
        }
    }
}
