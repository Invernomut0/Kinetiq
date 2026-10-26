// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import QuartzCore

/// Plays the open effect when a window is created.
///
/// The new window is parked off-screen the moment its app announces it, captured once it has been painted,
/// and drawn by the effect's shader (in the opening direction). It is moved back under the last frames of
/// the effect. If anything goes wrong the window is put back at once, so it is never left parked.
@MainActor
final class OpenEffectTrigger {
    private static let firstDelay: Duration = .milliseconds(120)
    private static let retryDelay: Duration = .milliseconds(100)
    private static let maxTries = 6
    /// Longest an effect may keep the window parked, whatever happens.
    private static let failsafe: TimeInterval = 15

    private let settings: Settings
    private let capture: WindowCapture
    private let player: CloseEffectPlayer
    /// True while a wobble animation owns the overlays and the windows.
    private let isBusy: () -> Bool
    private var inProgress = false

    init(settings: Settings, capture: WindowCapture, player: CloseEffectPlayer, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.capture = capture
        self.player = player
        self.isBusy = isBusy
    }

    func windowCreated(_ element: AXUIElement, pid: pid_t) {
        guard settings.enabled, settings.openEffect != .off, !inProgress, !isBusy(),
              pid != ProcessInfo.processInfo.processIdentifier, !AppExclusions.contains(pid: pid) else { return }
        inProgress = true
        let park = NSScreen.parkingPoint
        AXBridge.queue(for: pid).async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.25)
            // Park first, check after: every call before the move is time during which the new window can be seen.
            guard AXBridge.isStandardWindow(element), let frame = AXBridge.frame(of: element) else {
                Task { @MainActor in self?.inProgress = false }
                return
            }
            AXBridge.setPosition(element, park)
            guard !AXBridge.isFullScreen(element), let id = AXBridge.windowID(of: element),
                  frame.width >= 200, frame.height >= 120 else {
                AXBridge.setPosition(element, frame.origin)
                Task { @MainActor in self?.inProgress = false }
                return
            }
            Task { @MainActor in self?.begin(element, WindowInfo(id: id, pid: pid, frame: frame)) }
        }
    }

    /// The window is parked: wait for its content, then play the effect.
    private func begin(_ element: AXUIElement, _ info: WindowInfo) {
        var restored = false
        let restore: () -> Void = { [weak self] in
            guard !restored else { return }
            restored = true
            AXBridge.queue(for: element).async { AXBridge.setPosition(element, info.frame.origin) }
            self?.inProgress = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.failsafe) { restore() }

        Task {
            try? await Task.sleep(for: Self.firstDelay)
            for _ in 0..<Self.maxTries {
                if let frame = try? await capture.capture(info), frame.isPainted {
                    guard settings.enabled, let effect = player.effect(for: settings.openEffect) else { break }
                    let pointer = CGEvent(source: nil)?.location ?? CGPoint(x: info.frame.midX, y: info.frame.midY)
                    let started = player.play(
                        frame, windowFrame: info.frame, effect: effect, pointer: pointer,
                        durationScale: settings.closeDuration, nativeFade: false, opening: true, nearEnd: restore)
                    if started { return }
                    break
                }
                try? await Task.sleep(for: Self.retryDelay)
            }
            restore()
        }
    }
}
