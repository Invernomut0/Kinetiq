// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import KinetiqCore
import QuartzCore
import os

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
        let shield: Task<ScreenShield?, Never>
        let icon: Task<CGRect?, Never>
        let startedAt: CFTimeInterval
    }

    /// Area of a window, from its top-left corner, where the window buttons are.
    private static let buttonArea = CGSize(width: 110, height: 52)
    /// A capture that takes longer than this after the click is not worth waiting for: the click is replayed.
    private static let captureTimeout: CFTimeInterval = 0.5
    /// Frames the overlay shows the window before the real one is parked, as in a drag.
    private static let parkDelay: TimeInterval = 0.04
    /// Longest to wait for the system animation to take the window off screen.
    private static let animationTimeout: CFTimeInterval = 1.5

    private let settings: Settings
    private let capture: WindowCapture
    private let morph: MorphPlayer
    private let isBusy: () -> Bool
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "minimize")
    private let replay: (CGEvent, CGEvent) -> Void
    private var pending: Pending?

    init(settings: Settings, capture: WindowCapture, morph: MorphPlayer, isBusy: @escaping () -> Bool,
         replay: @escaping (CGEvent, CGEvent) -> Void) {
        self.settings = settings
        self.capture = capture
        self.morph = morph
        self.isBusy = isBusy
        self.replay = replay
    }

    /// A click on the button is being held back.
    var isPending: Bool { pending != nil }

    func cancel() {
        pending = nil
        morph.cancel()
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
        let shield = Task { await ScreenShield.capture(hiding: [info.id]) }
        let pid = info.pid
        let icon = Task<CGRect?, Never> {
            await withCheckedContinuation { continuation in
                AXBridge.urgentQueue.async { continuation.resume(returning: DockIcon.frame(forApp: pid)) }
            }
        }
        pending = Pending(info: info, buttonFrame: button, down: down, capture: task, shield: shield, icon: icon,
                          startedAt: CACurrentMediaTime())
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
        let shield = await click.shield.value
        let icon = await click.icon.value
        guard let frame, frame.isPainted, frame.pointSize == info.frame.size,
              CACurrentMediaTime() - click.startedAt < Self.captureTimeout, !isBusy(), !morph.isPlaying,
              let style = resolvedStyle() else {
            shield?.hide()
            replay(click.down, up)
            return
        }
        let element: AXUIElement? = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async {
                continuation.resume(returning: AXBridge.findWindow(info, hitPoint: click.buttonFrame.origin))
            }
        }
        guard let element else {
            shield?.hide()
            replay(click.down, up)
            return
        }

        // The shield goes up first, and the morph over it: the real window can then shrink towards the Dock unseen.
        shield?.show()
        let target = icon ?? fallbackIcon(near: info.frame)
        Self.log.notice("\(style.title, privacy: .public) into \(target.minX), \(target.minY) \(target.width)x\(target.height) (dock icon found: \(icon != nil))")
        let started = morph.play(frame, windowFrame: info.frame, icon: target, style: style,
                                 durationScale: settings.closeDuration) {}
        guard started else {
            shield?.hide()
            replay(click.down, up)
            return
        }

        // Parked and minimized in one go, so the system animation starts from a window that is not on screen.
        let park = NSScreen.parkingPoint
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.parkDelay) { [weak self] in
            AXBridge.urgentQueue.async {
                AXBridge.setPosition(element, park)
                AXBridge.setMinimized(element, true)
            }
            self?.finishWhenGone(info.id, element: element, origin: info.frame.origin, shield: shield)
        }
    }

    private func resolvedStyle() -> DockMorphStyle? {
        switch settings.minimizeEffect {
        case .off: return nil
        case .morph(let style): return style
        case .random: return DockMorphStyle.allCases.randomElement()
        }
    }

    /// Without a Dock icon to aim at, the window goes to the bottom middle of its screen.
    private func fallbackIcon(near frame: CGRect) -> CGRect {
        let screen = NSScreen.containing(cgPoint: CGPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.screens.first
        let bounds = screen?.cgFrame ?? frame
        return CGRect(x: bounds.midX - 28, y: bounds.maxY - 70, width: 56, height: 56)
    }

    /// Once the system animation has taken the window off screen, puts it back at its position (it stays minimized,
    /// so it comes back where it was) and drops the shield.
    private func finishWhenGone(_ id: CGWindowID, element: AXUIElement, origin: CGPoint, shield: ScreenShield?) {
        let began = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: .milliseconds(16), leeway: .nanoseconds(0))
        timer.setEventHandler {
            MainActor.assumeIsolated {
                guard WindowLocator.snapshot(of: id) == nil || CACurrentMediaTime() - began > Self.animationTimeout else { return }
                timer.cancel()
                AXBridge.urgentQueue.async { AXBridge.setPosition(element, origin) }
                shield?.hide()
            }
        }
        timer.resume()
    }
}
