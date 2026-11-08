// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import KinetiqCore

/// Animated state of a window overview: how far the windows have travelled from their real
/// positions, which one is highlighted, and the carousel/orbit position.
struct OverviewState: Equatable {
    /// 0 = every window at its real frame, 1 = arranged (may overshoot slightly while entering).
    var amount: Double = 0
    /// Cube carousel: fractional index of the window facing the viewer.
    var focus: Double = 0
    /// Orbit: rotation of the ring, in radians.
    var spin: Double = 0
    /// Per-window highlight, 0...1, eased by the caller.
    var hover: [Double] = []
}

struct OverviewPlacement: Equatable {
    let rect: CGRect
    /// The preset this window is drawn with: per-window angles plus the travel-scaled amplitude.
    let preset: EffectPreset
}

/// Pure geometry shared by the desktop overview and its panel preview, so both look the same
/// and hit-testing matches what is drawn. Global, Y-down points.
enum OverviewLayout {
    static let enterDuration = 0.42
    static let leaveDuration = 0.3

    /// Back-out easing: overshoots a little, then settles, like a spring.
    static func enter(_ t: Double) -> Double {
        let t = min(1, max(0, t)) - 1
        return 1 + 2.2 * t * t * t + 1.2 * t * t
    }

    static func leave(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Placements in input order plus the back-to-front drawing order.
    static func place(effect: EffectID, preset: EffectPreset, homes: [CGRect], stage: CGRect,
                      state: OverviewState) -> (placements: [OverviewPlacement], order: [Int]) {
        let n = homes.count
        guard n > 0, stage.width > 0, stage.height > 0 else { return ([], []) }
        let hover = homes.indices.map { $0 < state.hover.count ? min(1, max(0, state.hover[$0])) : 0 }
        var targets: [CGRect] = []
        var presets: [EffectPreset] = []
        var depth: [Double] = []
        func fit(_ home: CGRect, in size: CGSize) -> CGSize {
            let scale = min(size.width / max(1, home.width), size.height / max(1, home.height))
            return CGSize(width: home.width * scale, height: home.height * scale)
        }
        func centered(_ size: CGSize, at point: CGPoint, scale: Double) -> CGRect {
            CGRect(x: point.x - size.width * scale / 2, y: point.y - size.height * scale / 2,
                   width: size.width * scale, height: size.height * scale)
        }
        switch effect {
        case .orbit:
            let radius = preset.value("radius", at: 0)
            let rx = stage.width * (0.18 + 0.42 * radius), ry = rx * 0.32
            let card = CGSize(width: stage.width / (n > 5 ? 4.2 : 3.2), height: stage.height / (n > 5 ? 3.6 : 2.8))
            let speed = preset.value("speed", at: 0)
            for (i, home) in homes.enumerated() {
                let theta = 2 * Double.pi * Double(i) / Double(n) + state.spin + preset.value("angle", at: 0) * .pi / 180
                let front = (sin(theta) + 1) / 2
                let center = CGPoint(x: stage.midX + cos(theta) * rx, y: stage.midY + sin(theta) * ry)
                targets.append(centered(fit(home, in: card), at: center, scale: 0.58 + 0.42 * front + 0.1 * hover[i]))
                var p = preset
                // The shader turns each window by sin(phase); choose the phase so windows face the centre.
                let phase = theta - .pi / 2
                p.parameters["angle"] = min(180, max(-180, remainder((phase - .pi * speed) * 180 / .pi, 360)))
                p.parameters["radius"] = 0.1
                presets.append(p)
                depth.append(front + hover[i])
            }
        case .workspaceCube:
            let card = CGSize(width: stage.width * 0.5, height: stage.height * 0.6)
            let maxYaw = preset.value("angle", at: 0)
            for (i, home) in homes.enumerated() {
                let d = Double(i) - state.focus
                let size = fit(home, in: card)
                let side = min(1, abs(d)) * (d < 0 ? -1 : 1)
                let scale = 1 - min(abs(d), 3) * 0.16 + 0.06 * hover[i]
                // Cards beyond the first neighbour stack closer, like a cover flow, and stay on screen.
                let room = max(0, stage.width / 2 - size.width * 0.62 - size.width * 0.3)
                let step = min(size.width * 0.22, room / Double(max(1, n - 2)))
                var x = stage.midX + side * size.width * 0.62 + (abs(d) > 1 ? (d - side) * step : 0)
                let half = size.width * scale / 2
                x = min(stage.maxX - half, max(stage.minX + half, x))
                targets.append(centered(size, at: CGPoint(x: x, y: stage.midY), scale: scale))
                var p = preset
                p.parameters["angle"] = -side * abs(maxYaw == 0 ? 50 : maxYaw)
                presets.append(p)
                depth.append(-abs(d) + hover[i] * 0.1)
            }
        default: // Exposé 3D and anything else: a tilted grid.
            let columns = min(4, max(1, Int(ceil(sqrt(Double(n))))))
            let rows = Int(ceil(Double(n) / Double(columns)))
            // The Exposé shader shrinks each surface by up to 38 %; enlarge the target to fill its cell.
            let shrink = 1 - min(0.65, preset.value("amplitude", at: 0) * 0.38)
            let cellWidth = stage.width / CGFloat(columns), cellHeight = stage.height / CGFloat(rows)
            for (i, home) in homes.enumerated() {
                let row = i / columns
                let inRow = row == rows - 1 ? n - row * columns : columns
                // An incomplete last row is centred.
                let offset = CGFloat(columns - inRow) * cellWidth / 2
                let cell = CGRect(x: stage.minX + offset + CGFloat(i % columns) * cellWidth, y: stage.minY + CGFloat(row) * cellHeight,
                                  width: cellWidth, height: cellHeight).insetBy(dx: 18, dy: 18)
                let size = fit(home, in: cell.size)
                targets.append(centered(size, at: CGPoint(x: cell.midX, y: cell.midY), scale: (0.82 + 0.1 * hover[i]) / shrink))
                var p = preset
                // The highlighted window straightens up to face you.
                p.parameters["angle"] = preset.value("angle", at: 0) * (1 - hover[i])
                presets.append(p)
                depth.append(hover[i])
            }
        }
        let amount = state.amount
        let placements = homes.indices.map { i -> OverviewPlacement in
            let a = homes[i], b = targets[i]
            let rect = CGRect(x: a.minX + (b.minX - a.minX) * amount, y: a.minY + (b.minY - a.minY) * amount,
                              width: max(1, a.width + (b.width - a.width) * amount),
                              height: max(1, a.height + (b.height - a.height) * amount))
            var p = presets[i]
            p.parameters["amplitude"] = min(2, max(0, preset.value("amplitude", at: 0) * min(1.2, max(0, amount))))
            return OverviewPlacement(rect: rect, preset: p)
        }
        // Near home, keep the real stacking (index 0 is the frontmost window); once arranged, depth.
        let order = amount < 0.35 ? Array(homes.indices.reversed())
            : homes.indices.sorted { depth[$0] == depth[$1] ? $0 > $1 : depth[$0] < depth[$1] }
        return (placements, order)
    }

    /// Scattered "desktop" frames for the panel preview, inside a virtual screen.
    static func sampleHomes(in screen: CGRect, count: Int) -> [CGRect] {
        let layouts: [(Double, Double, Double, Double)] = [
            (0.06, 0.10, 0.42, 0.46), (0.40, 0.06, 0.46, 0.50), (0.12, 0.46, 0.38, 0.40),
            (0.52, 0.44, 0.40, 0.44), (0.30, 0.26, 0.40, 0.42), (0.62, 0.18, 0.32, 0.36)]
        return layouts.prefix(count).map { x, y, w, h in
            CGRect(x: screen.minX + screen.width * x, y: screen.minY + screen.height * y,
                   width: screen.width * w, height: screen.height * h)
        }
    }
}
