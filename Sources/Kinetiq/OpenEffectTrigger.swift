// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices
import KinetiqCore
import QuartzCore
import os

/// Plays the open effect when a window is created.
///
/// The new window is never hidden: once its own pop-in animation is over, it is captured as it is and handed to the
/// jelly model, which plays one of the `WobbleEntrance`s. That way there is no flash and no empty moment.
@MainActor
final class OpenEffectTrigger {
    private static let settleTime: CFTimeInterval = 0.05
    private static let settleTimeout: CFTimeInterval = 0.8
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "open")

    private let settings: Settings
    /// True while a wobble animation owns the overlays and the windows.
    private let isBusy: () -> Bool
    private var inProgress = false
    /// A new window is waiting for its pop-in animation to end.
    var isActive: Bool { inProgress }
    /// Called as soon as a new window is going to get an effect.
    var onStarted: (() -> Void)?
    /// Called with a window that is ready for its entrance.
    var startWobbleEntrance: ((AXUIElement, WindowInfo, WobbleEntrance) -> Void)?

    init(settings: Settings, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.isBusy = isBusy
    }

    private func entrance() -> WobbleEntrance? {
        switch settings.openEffect {
        case .off: return nil
        case .wobble(let entrance): return entrance
        case .random: return WobbleEntrance.allCases.randomElement()
        }
    }

    func windowCreated(_ element: AXUIElement, pid: pid_t) {
        guard settings.enabled, !inProgress, !isBusy(), pid != ProcessInfo.processInfo.processIdentifier,
              !AppExclusions.contains(pid: pid), let entrance = entrance() else { return }
        inProgress = true
        onStarted?()
        AXBridge.urgentQueue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.25)
            guard AXBridge.isStandardWindow(element), !AXBridge.isFullScreen(element), let frame = AXBridge.frame(of: element),
                  let id = AXBridge.windowID(of: element), frame.width >= 200, frame.height >= 120 else {
                Self.log.notice("skipped: not a standard, windowed, big enough window")
                Task { @MainActor in self?.inProgress = false }
                return
            }
            let info = WindowInfo(id: id, pid: pid, frame: frame)
            Task { @MainActor in self?.begin(element, info, entrance) }
        }
    }

    /// Waits until the window stops moving and resizing, then hands it over.
    private func begin(_ element: AXUIElement, _ initial: WindowInfo, _ entrance: WobbleEntrance) {
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
            Self.log.notice("\(entrance.title, privacy: .public) at \(frame.minX), \(frame.minY) \(frame.width)x\(frame.height)")
            startWobbleEntrance?(element, WindowInfo(id: initial.id, pid: initial.pid, frame: frame), entrance)
        }
    }
}
