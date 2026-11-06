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
    private let liquid: LiquidEffectPlayer?
    private let isBusy: () -> Bool
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "minimize")
    private let replay: (CGEvent, CGEvent) -> Void
    private var pending: Pending?
    private var preparing = false
    /// Invalidates an async capture/AX lookup if the controller cancels meanwhile.
    private var generation = UUID()
    private var parked: CatalogWindowLease?
    private var parkedShield: ScreenShield?
    private var restoreTimer: DispatchSourceTimer?

    init(settings: Settings, capture: WindowCapture, morph: MorphPlayer, liquid: LiquidEffectPlayer?, isBusy: @escaping () -> Bool,
         replay: @escaping (CGEvent, CGEvent) -> Void) {
        self.settings = settings
        self.capture = capture
        self.morph = morph
        self.liquid = liquid
        self.isBusy = isBusy
        self.replay = replay
    }

    /// A click on the button is being held back.
    var isPending: Bool { pending != nil || preparing }

    func cancel() {
        generation = UUID()
        CatalogRuntime.shared.stop()
        restoreTimer?.cancel(); restoreTimer = nil
        pending?.capture.cancel(); pending?.shield.cancel(); pending?.icon.cancel()
        pending = nil
        preparing = false
        morph.cancel()
        liquid?.cancelAll()
    }

    /// Returns true if the click is held back.
    func mouseDown(_ event: CGEvent, windows: WindowList) -> Bool {
        let point = event.location
        guard settings.enabled, (settings.minimizeEffect != .off || CatalogStore.shared.assigned(to: .minimize) != nil),
              !isPending, parked == nil, !isBusy(), !CatalogRuntime.shared.isPlaying,
              let info = WindowLocator.window(at: point, in: windows) else { return false }
        guard info.pid != ProcessInfo.processInfo.processIdentifier, !AppExclusions.contains(pid: info.pid) else { return false }
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
        let token = generation
        preparing = true
        Task {
            defer { if generation == token { preparing = false } }
            await minimize(click, up: up, token: token)
        }
        return true
    }

    private func minimize(_ click: Pending, up: CGEvent, token: UUID) async {
        let info = click.info
        let frame = await click.capture.value
        let shield = await click.shield.value
        let icon = await click.icon.value
        let assigned = CatalogStore.shared.assigned(to: .minimize)
        guard generation == token else { shield?.hide(); return }
        guard settings.enabled, let frame, frame.isPainted, frame.pointSize == info.frame.size,
              CACurrentMediaTime() - click.startedAt < Self.captureTimeout, !isBusy(), !morph.isPlaying,
              assigned != nil || resolvedChoice() != nil else {
            shield?.hide()
            replay(click.down, up)
            return
        }
        let element: AXUIElement? = await withCheckedContinuation { continuation in
            AXBridge.queue(for: info.pid).async {
                let element = AXBridge.findWindow(info, hitPoint: click.buttonFrame.origin)
                guard let element, AXBridge.windowID(of: element) == info.id,
                      AXBridge.isStandardWindow(element), !AXBridge.isFullScreen(element),
                      AXBridge.frame(of: element) == info.frame else { continuation.resume(returning: nil); return }
                continuation.resume(returning: element)
            }
        }
            guard generation == token else { shield?.hide(); return }
            guard settings.enabled, !isBusy(), !CatalogRuntime.shared.isPlaying, let element,
              CatalogStore.shared.assigned(to: .minimize) == assigned else {
            shield?.hide()
            replay(click.down, up)
            return
        }

        // The shield goes up first, and the morph over it: the real window can then shrink towards the Dock unseen.
        shield?.show()
        let target = icon ?? fallbackIcon(near: info.frame)
        let started: Bool
        if let assigned {
            started = CatalogRuntime.shared.playCaptured(frame, windowFrame: info.frame, preset: assigned)
        } else {
            switch resolvedChoice() ?? .off {
            case .liquid:
                Self.log.notice("Liquid minimize: window \(info.id)")
                started = liquid?.play(frame, windowFrame: info.frame, durationScale: settings.closeDuration) ?? false
            case .morph(let style):
                Self.log.notice("\(style.title, privacy: .public) into \(target.minX), \(target.minY) \(target.width)x\(target.height) (dock icon found: \(icon != nil))")
                started = morph.play(frame, windowFrame: info.frame, icon: target, style: style,
                                     durationScale: settings.closeDuration) {}
            case .off, .random:
                started = false
            }
        }
        guard started else {
            shield?.hide()
            replay(click.down, up)
            return
        }

        // Parked and minimized in one go, so the system animation starts from a window that is not on screen.
        let lease = CatalogWindowLease(element: element, info: info)
        parked = lease; parkedShield = shield
        CatalogRuntime.shared.ownMinimizeLease(lease) { [weak self] in
            shield?.hide()
            guard let self, self.parked === lease else { return }
            self.parked = nil; self.parkedShield = nil
            self.restoreTimer?.cancel(); self.restoreTimer = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.parkDelay) { [weak self] in
            guard let self, self.generation == token, self.settings.enabled else {
                CatalogRuntime.shared.releaseMinimizeLease(lease)
                return
            }
            Task { @MainActor in
                let didPark = await lease.park()
                guard self.generation == token else { return }
                guard self.settings.enabled, didPark else {
                    self.finish(lease, click: click, up: up, token: token, replayClick: true)
                    return
                }
                lease.minimize()
                self.finishWhenMinimized(lease, click: click, up: up, token: token)
            }
        }
    }

    private func resolvedChoice() -> MinimizeEffectChoice? {
        switch settings.minimizeEffect {
        case .off: return nil
        case .liquid: return .liquid
        case .morph(let style): return .morph(style)
        case .random: return DockMorphStyle.allCases.map(MinimizeEffectChoice.morph).randomElement()
        }
    }

    /// Without a Dock icon to aim at, the window goes to the bottom middle of its screen.
    private func fallbackIcon(near frame: CGRect) -> CGRect {
        let screen = NSScreen.containing(cgPoint: CGPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.screens.first
        let bounds = screen?.cgFrame ?? frame
        return CGRect(x: bounds.midX - 28, y: bounds.maxY - 70, width: 56, height: 56)
    }

    /// Parking already removes the window from the on-screen list; only AX proves
    /// the native action completed. Keep ownership and the shield until restoration.
    private func finishWhenMinimized(_ lease: CatalogWindowLease, click: Pending, up: CGEvent, token: UUID) {
        let began = CACurrentMediaTime()
        var checking = false
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { timer.cancel(); CatalogRuntime.shared.releaseMinimizeLease(lease); return }
                if self.generation != token || !self.settings.enabled {
                    timer.cancel(); CatalogRuntime.shared.releaseMinimizeLease(lease); return
                }
                if checking, CACurrentMediaTime() - began >= Self.animationTimeout {
                    timer.cancel()
                    self.finish(lease, click: click, up: up, token: token, replayClick: false)
                    return
                }
                guard !checking else { return }
                checking = true
                Task { @MainActor in
                    let minimized = await lease.isMinimized()
                    checking = false
                    guard self.generation == token, self.parked === lease else { timer.cancel(); return }
                    guard minimized == true || CACurrentMediaTime() - began >= Self.animationTimeout else { return }
                    timer.cancel()
                    // Retry the original click only after a definite native rejection,
                    // origin restoration and a final exact-window safety check.
                    self.finish(lease, click: click, up: up, token: token, replayClick: minimized == false)
                }
            }
        }
        restoreTimer = timer
        timer.resume()
    }

    private func finish(_ lease: CatalogWindowLease, click: Pending, up: CGEvent, token: UUID, replayClick: Bool) {
        guard generation == token else { return }
        restoreTimer?.cancel(); restoreTimer = nil
        if replayClick {
            morph.cancel(); liquid?.cancelAll()
        }
        CatalogRuntime.shared.releaseMinimizeLease(lease) { [weak self] in
            guard let self, replayClick else { return }
            Task { @MainActor in
                let minimized = await lease.isMinimized()
                guard minimized == false, self.generation == token, self.settings.enabled,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == click.info.pid,
                      WindowLocator.window(at: up.location)?.id == click.info.id,
                      WindowLocator.snapshot(of: click.info.id)?.frame == click.info.frame else { return }
                self.replay(click.down, up)
            }
        }
        if replayClick { CatalogRuntime.shared.stop() }
    }
}
