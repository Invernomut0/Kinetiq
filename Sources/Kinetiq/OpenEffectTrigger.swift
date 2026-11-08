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
/// Legacy entrances retain their original jelly path. An explicitly assigned catalog
/// preset captures the painted window first, then uses the runtime's reversible AX lease.
@MainActor
final class OpenEffectTrigger {
    private static let settleTime: CFTimeInterval = 0.05
    private static let settleTimeout: CFTimeInterval = 0.8
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "open")

    private let settings: Settings
    /// True while a wobble animation owns the overlays and the windows.
    private let isBusy: () -> Bool
    private var inProgress = false
    private var generation = UUID()
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

    func cancelAll() {
        generation = UUID()
        inProgress = false
        CatalogRuntime.shared.stop()
    }

    func windowCreated(_ element: AXUIElement, pid: pid_t) {
                guard settings.enabled, !inProgress, !isBusy(), !CatalogRuntime.shared.isPlaying, pid != ProcessInfo.processInfo.processIdentifier,
              !AppExclusions.contains(pid: pid) else { return }
                let assigned = CatalogStore.shared.assigned(to: .open)
                guard assigned != nil || CatalogStore.shared.assignedCustom(to: .open) != nil || entrance() != nil else { return }
                let token = generation
        inProgress = true
        onStarted?()
        AXBridge.urgentQueue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.25)
            guard AXBridge.isStandardWindow(element), !AXBridge.isFullScreen(element), let frame = AXBridge.frame(of: element),
                  let id = AXBridge.windowID(of: element), frame.width >= 200, frame.height >= 120 else {
                Task { @MainActor in
                    if self?.generation == token {
                        Self.log.notice("skipped: not a standard, windowed, big enough window")
                        self?.inProgress = false
                    }
                }
                return
            }
            let info = WindowInfo(id: id, pid: pid, frame: frame)
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.begin(element, info)
            }
        }
    }

    /// Waits until the window stops moving and resizing, then hands it over.
    private func begin(_ element: AXUIElement, _ initial: WindowInfo) {
        let token = generation
        Task {
            defer { if generation == token { inProgress = false } }
            var frame = initial.frame
            var stableSince = CACurrentMediaTime()
            let deadline = stableSince + Self.settleTimeout
            while CACurrentMediaTime() < deadline {
                try? await Task.sleep(for: .milliseconds(16))
                guard generation == token, settings.enabled else { return }
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
            guard generation == token else { return }
            inProgress = false
            guard settings.enabled, !isBusy(), !CatalogRuntime.shared.isPlaying, !AppExclusions.contains(pid: initial.pid) else { return }
            if let custom = CatalogStore.shared.assignedCustom(to: .open) {
                await CatalogRuntime.shared.playDocument(custom.document, windowID: initial.id)
                return
            }
            if let assigned = CatalogStore.shared.assigned(to: .open) {
                // Runtime captures the painted, on-screen window BEFORE it parks it.
                await CatalogRuntime.shared.play(assigned, windowID: initial.id)
                return
            }
            guard let entrance = entrance() else { return }
            Self.log.notice("\(entrance.title, privacy: .public) at \(frame.minX), \(frame.minY) \(frame.width)x\(frame.height)")
            startWobbleEntrance?(element, WindowInfo(id: initial.id, pid: initial.pid, frame: frame), entrance)
        }
    }
}
