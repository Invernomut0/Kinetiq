// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import QuartzCore
import os

/// Plays the open effect when a window is created.
///
/// The new window is parked off-screen the moment its app announces it, captured once it has been painted,
/// and drawn by the effect's shader (in the opening direction). It is moved back under the last frames of
/// the effect. If anything goes wrong the window is put back at once, so it is never left parked.
@MainActor
final class OpenEffectTrigger {
    private static let settleTime: CFTimeInterval = 0.05
    private static let settleTimeout: CFTimeInterval = 0.8
    /// Fraction of the effect skipped by the "skip the start" trick.
    private static let skippedStart: Float = 0.25
    private static let retryDelay: Duration = .milliseconds(60)
    private static let maxTries = 6
    /// Longest an effect may keep the window parked, whatever happens.
    private static let failsafe: TimeInterval = 15

    private let settings: Settings
    private let capture: WindowCapture
    private let player: CloseEffectPlayer
    /// True while a wobble animation owns the overlays and the windows.
    private let isBusy: () -> Bool
    private var inProgress = false
    /// An open effect is on its way: the window is parked or being revealed.
    var isActive: Bool { inProgress }
    /// Called with the window's final frame once the effect has finished.
    var onFinished: ((CGRect) -> Void)?
    /// Called as soon as a new window is going to get an effect.
    var onStarted: (() -> Void)?
    /// Called with a window that was left visible and should pop with the jelly effect.
    var startWobblePop: ((AXUIElement, WindowInfo) -> Void)?
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "open")

    init(settings: Settings, capture: WindowCapture, player: CloseEffectPlayer, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.capture = capture
        self.player = player
        self.isBusy = isBusy
    }

    func windowCreated(_ element: AXUIElement, pid: pid_t) {
        Self.log.notice("window created, pid \(pid), busy \(self.inProgress), effect \(self.settings.openEffect.rawValue, privacy: .public)")
        let keepVisible = settings.openTrick == .keepVisible
        guard settings.enabled, settings.openEffect != .off || keepVisible, !inProgress, !isBusy(),
              pid != ProcessInfo.processInfo.processIdentifier, !AppExclusions.contains(pid: pid) else { return }
        inProgress = true
        onStarted?()
        let park = NSScreen.parkingPoint
        AXBridge.urgentQueue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.25)
            // Park first, check after: every call before the move is time during which the new window can be seen.
            guard AXBridge.isStandardWindow(element), let frame = AXBridge.frame(of: element) else {
                Self.log.notice("skipped: not a standard window or no frame")
                Task { @MainActor in self?.inProgress = false }
                return
            }
            if !keepVisible { AXBridge.setPosition(element, park) }
            guard !AXBridge.isFullScreen(element), let id = AXBridge.windowID(of: element),
                  frame.width >= 200, frame.height >= 120 else {
                Self.log.notice("skipped after parking: full screen, no id or too small")
                if !keepVisible { AXBridge.setPosition(element, frame.origin) }
                Task { @MainActor in self?.inProgress = false }
                return
            }
            let info = WindowInfo(id: id, pid: pid, frame: frame)
            Task { @MainActor in
                if keepVisible { self?.beginWobblePop(element, info) } else { self?.begin(element, info) }
            }
        }
    }

    /// The window stays where it is. Once its pop-in animation is over it is handed to the jelly effect.
    private func beginWobblePop(_ element: AXUIElement, _ initial: WindowInfo) {
        Task {
            var frame = initial.frame
            var stableSince = CACurrentMediaTime()
            let deadline = stableSince + Self.settleTimeout
            while CACurrentMediaTime() < deadline {
                try? await Task.sleep(for: .milliseconds(16))
                let current: CGRect? = await withCheckedContinuation { continuation in
                    AXBridge.urgentQueue.async { continuation.resume(returning: AXBridge.frame(of: element)) }
                }
                guard let current else { continue }
                let now = CACurrentMediaTime()
                if abs(current.minX - frame.minX) > 0.5 || abs(current.minY - frame.minY) > 0.5
                    || abs(current.width - frame.width) > 0.5 || abs(current.height - frame.height) > 0.5 {
                    frame = current
                    stableSince = now
                } else if now - stableSince >= Self.settleTime {
                    break
                }
            }
            inProgress = false
            guard settings.enabled, !isBusy() else { return }
            Self.log.notice("wobble pop at \(frame.minX), \(frame.minY) \(frame.width)x\(frame.height)")
            startWobblePop?(element, WindowInfo(id: initial.id, pid: initial.pid, frame: frame))
        }
    }

    /// A new window usually pops in with an animation, so its size and position change for a moment after the app
    /// announces it. Waits until the size holds still and returns the frame it ends at: the animation keeps the
    /// window's center, so the final origin follows from the final size.
    private func settledFrame(of element: AXUIElement, from initial: CGRect) async -> CGRect {
        let center = CGPoint(x: initial.midX, y: initial.midY)
        var size = initial.size
        var stableSince = CACurrentMediaTime()
        let deadline = stableSince + Self.settleTimeout
        while CACurrentMediaTime() < deadline {
            try? await Task.sleep(for: .milliseconds(16))
            let current: CGSize? = await withCheckedContinuation { continuation in
                AXBridge.urgentQueue.async { continuation.resume(returning: AXBridge.frame(of: element)?.size) }
            }
            guard let current else { continue }
            let now = CACurrentMediaTime()
            if abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 {
                size = current
                stableSince = now
            } else if now - stableSince >= Self.settleTime {
                break
            }
        }
        return CGRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    /// The window is parked: wait for its content, then play the effect.
    private func begin(_ element: AXUIElement, _ initial: WindowInfo) {
        var finalFrame = initial.frame
        var handedOver = false
        // Moves the window back, waits until it is really there, and only then lets the overlay go: the overlay keeps
        // drawing the finished window meanwhile, so there is no moment in which neither is on screen.
        let handOver: () -> Void = { [weak self] in
            guard !handedOver else { return }
            handedOver = true
            let target = finalFrame.origin
            AXBridge.urgentQueue.async { AXBridge.setPosition(element, target) }
            self?.waitUntilBack(id: initial.id, at: target) {
                guard let self else { return }
                self.player.releaseHeld()
                self.inProgress = false
                self.onFinished?(finalFrame)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.failsafe) { handOver() }

        Task {
            let settled = await settledFrame(of: element, from: initial.frame)
            finalFrame = settled
            let info = WindowInfo(id: initial.id, pid: initial.pid, frame: settled)
            Self.log.notice("settled at \(settled.minX), \(settled.minY) \(settled.width)x\(settled.height)")
            for attempt in 0..<Self.maxTries {
                var captured: CapturedFrame?
                do {
                    captured = try await capture.capture(info)
                } catch {
                    Self.log.notice("capture failed: \(String(describing: error), privacy: .public)")
                }
                Self.log.notice("attempt \(attempt): captured \(captured != nil), painted \(captured?.isPainted ?? false)")
                if let frame = captured, frame.isPainted {
                    guard settings.enabled, let effect = player.effect(for: settings.openEffect) else { break }
                    let pointer = CGEvent(source: nil)?.location ?? CGPoint(x: info.frame.midX, y: info.frame.midY)
                    let started = player.play(
                        frame, windowFrame: info.frame, effect: effect, pointer: pointer,
                        durationScale: settings.closeDuration, nativeFade: false, opening: true, onFinish: handOver,
                        holdLastFrame: true, startProgress: settings.openTrick == .skipStart ? Self.skippedStart : 0)
                    if started { return }
                    Self.log.notice("effect could not start")
                    break
                }
                try? await Task.sleep(for: Self.retryDelay)
            }
            handOver()
        }
    }

    /// Polls (every millisecond, like a drag does) until the window is on screen at `target`, or gives up.
    private func waitUntilBack(id: CGWindowID, at target: CGPoint, then done: @escaping () -> Void) {
        let began = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .nanoseconds(0))
        timer.setEventHandler {
            MainActor.assumeIsolated {
                let frame = WindowLocator.frame(of: id)
                let back = frame.map { abs($0.minX - target.x) <= 8 && abs($0.minY - target.y) <= 8 } ?? false
                guard back || CACurrentMediaTime() - began > 0.5 else { return }
                timer.cancel()
                Self.log.notice("back on screen after \(((CACurrentMediaTime() - began) * 1000), format: .fixed(precision: 0)) ms")
                done()
            }
        }
        timer.resume()
    }
}
