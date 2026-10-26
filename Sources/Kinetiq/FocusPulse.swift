// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore

/// A glow in the accent color that flashes around the window that has just taken the focus.
/// It is a click-through overlay drawn with Core Animation: nothing is captured or moved.
@MainActor
final class FocusPulse {
    private static let margin: CGFloat = 36
    private static let cornerRadius: CGFloat = 14
    private static let duration: CFTimeInterval = 0.6
    /// Pulses closer together than this are dropped (switching apps quickly would flash constantly).
    private static let minInterval: CFTimeInterval = 0.35

    private var window: NSWindow?
    private let glow = CALayer()
    private var lastPulse: CFTimeInterval = 0

    /// Stops a glow that is showing.
    func cancel() {
        glow.removeAllAnimations()
        window?.orderOut(nil)
    }

    /// `frame` is the window in global CoreGraphics coordinates (origin at the top left of the main screen).
    func pulse(around frame: CGRect) {
        let now = CACurrentMediaTime()
        guard now - lastPulse >= Self.minInterval, let primary = NSScreen.screens.first,
              frame.width >= 80, frame.height >= 40, !coversAScreen(frame) else { return }
        lastPulse = now

        let accent = NSColor.controlAccentColor
        let area = NSRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)
            .insetBy(dx: -Self.margin, dy: -Self.margin)
        let window = overlayWindow()
        window.setFrame(area, display: false)
        glow.frame = CGRect(x: Self.margin, y: Self.margin, width: frame.width, height: frame.height)
        glow.cornerRadius = Self.cornerRadius
        glow.borderWidth = 3
        glow.borderColor = accent.cgColor
        glow.shadowColor = accent.cgColor
        glow.shadowRadius = 16
        glow.shadowOpacity = 1
        glow.shadowOffset = .zero

        glow.removeAllAnimations()
        window.orderFrontRegardless()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, CACurrentMediaTime() - self.lastPulse >= Self.duration - 0.05 else { return }
                self.window?.orderOut(nil)
            }
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.2, 1]
        fade.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        fade.duration = Self.duration
        fade.isRemovedOnCompletion = true
        glow.opacity = 0
        glow.add(fade, forKey: "pulse")
        CATransaction.commit()
    }

    private func coversAScreen(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.cgFrame.intersection(frame)
            return !overlap.isNull && overlap.width * overlap.height >= 0.95 * screen.cgFrame.width * screen.cgFrame.height
        }
    }

    private func overlayWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let content = NSView()
        content.wantsLayer = true
        content.layer?.addSublayer(glow)
        window.contentView = content
        self.window = window
        return window
    }
}
