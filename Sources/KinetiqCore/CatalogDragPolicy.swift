// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import simd

/// A value snapshot of an explicit drag assignment. Contains no desktop queries,
/// clocks or mutable preference storage; callers supply real global Y-down geometry.
public struct CatalogDragPolicy: Sendable {
    public let preset: EffectPreset

    public init?(preset: EffectPreset?) {
        guard let preset, preset.trigger == .drag,
              [.wobbly, .float, .ripple, .magnet, .gravity].contains(preset.effect) else { return nil }
        self.preset = preset
    }

    /// Warp the local monotonic clock once, then let each keyframe's outgoing
    /// curve interpolate its segment. Past duration, hold the final parameter values.
    public func parameters(at elapsed: Double) -> [String: Double] {
        let duration = preset.duration.isFinite ? max(0.1, preset.duration) : 1
        let time = preset.curve.value(at: elapsed / duration) * duration
        return Dictionary(uniqueKeysWithValues: EffectCatalog.descriptor(preset.effect).parameters.map {
            ($0.id, preset.value($0.id, at: time))
        })
    }

    /// Only Wobbly replaces spring/friction. Speed is a separate simulation-rate
    /// multiplier, so the legacy mass and speedup keep their documented meanings.
    public func wobblySettings(base: KinetiqSettings, at elapsed: Double) -> KinetiqSettings {
        guard preset.effect == .wobbly else { return base }
        let values = parameters(at: elapsed)
        var result = base
        result.spring = Float(values["stiffness"] ?? Double(base.spring))
        result.friction = Float(values["friction"] ?? Double(base.friction))
        return result
    }

    /// Float is ambient throughout a held gesture, even beyond the preset's
    /// parameter timeline. The supplied release offset fades exactly to zero.
    public func ambientOffset(size: SIMD2<Float>, elapsed: Double) -> SIMD2<Float> {
        guard preset.effect == .float, elapsed.isFinite else { return .zero }
        let values = parameters(at: elapsed)
        let phase = elapsed * (values["frequency"] ?? 0.5) * (values["speed"] ?? 1) * 2 * .pi
        let distance = Double(size.y) * (values["distance"] ?? 0.03) * (values["amplitude"] ?? 1)
        return SIMD2(Float(sin(phase * 0.5) * distance * 0.25), Float(sin(phase) * distance))
    }

    public func releaseOffset(_ offset: SIMD2<Float>, elapsed: Double) -> SIMD2<Float> {
        let duration = min(0.5, max(0.1, preset.duration))
        let progress = AnimationCurve.easeOut.value(at: elapsed / duration)
        return offset * Float(1 - progress)
    }

    public var releaseDuration: Double {
        let duration = preset.duration.isFinite ? preset.duration : 1
        return min(12, max(0.1, duration))
    }

    /// Includes the shadow ring in the actual mesh budget. At least three total
    /// tiles per axis keeps the ring and a nonempty interior valid even at tiny limits.
    public static func meshTiles(requested: Int, meshLimit: Int) -> Int {
        let totalLimit = min(64, max(3, meshLimit))
        return min(max(3, requested), totalLimit - 2)
    }

    /// Nearest independent edge on each axis, but only across overlapping edge
    /// segments. A window hundreds of points above cannot attract our X edge.
    /// Radius is in points; zero amplitude/strength is an exact native fallback.
    public static func magnetOrigin(frame: CGRect, bounds: CGRect, targets: [CGRect],
                                    parameters: [String: Double], dt: Double,
                                    snap: Bool = false) -> CGPoint {
        guard valid(frame), valid(bounds), dt.isFinite, dt > 0 else { return frame.origin }
        func value(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            let raw = parameters[key] ?? fallback
            return raw.isFinite ? min(range.upperBound, max(range.lowerBound, raw)) : fallback
        }
        let radius = value("radius", 160, 10...600)
        let strength = value("strength", 1, 0...2) * value("amplitude", 1, 0...2)
        guard strength > 0 else { return frame.origin }
        let speed = value("speed", 1, 0.1...4)
        let highX = max(bounds.minX, bounds.maxX - frame.width)
        let highY = max(bounds.minY, bounds.maxY - frame.height)
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        if overlaps(frame.minY, frame.maxY, bounds.minY, bounds.maxY) {
            xs = [bounds.minX, highX]
        }
        if overlaps(frame.minX, frame.maxX, bounds.minX, bounds.maxX) {
            ys = [bounds.minY, highY]
        }
        for target in targets where valid(target) && target.intersects(bounds) {
            if overlaps(frame.minY, frame.maxY, target.minY, target.maxY) {
                xs += [target.minX - frame.width, target.maxX]
            }
            if overlaps(frame.minX, frame.maxX, target.minX, target.maxX) {
                ys += [target.minY - frame.height, target.maxY]
            }
        }
        func attract(_ origin: CGFloat, candidates: [CGFloat], low: CGFloat, high: CGFloat) -> CGFloat {
            let nearby = candidates.filter { $0 >= low && $0 <= high && abs($0 - origin) <= radius }
            guard let target = nearby.min(by: { abs($0 - origin) < abs($1 - origin) }) else { return origin }
            let distance = abs(target - origin)
            if snap && distance <= 1 { return target }
            let proximity = max(0, 1 - Double(distance) / radius)
            let follow = 1 - exp(-18 * strength * speed * proximity * min(0.1, dt))
            return origin + (target - origin) * follow
        }
        return CGPoint(x: attract(frame.minX, candidates: xs, low: bounds.minX, high: highX),
                       y: attract(frame.minY, candidates: ys, low: bounds.minY, high: highY))
    }

    private static func overlaps(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> Bool {
        min(b, d) > max(a, c)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }
}