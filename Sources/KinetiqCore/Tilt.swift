// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import simd

/// Perspective tilt of a window that is being moved: it leans into the movement and flattens again at rest.
public enum Tilt {
    /// Largest lean, in radians.
    public static let maxAngle: Float = 0.38
    /// Speed (points per second) at which the lean reaches `maxAngle`.
    public static let fullSpeed: Float = 2400
    /// Distance from the viewer to the window plane, in points: the smaller, the stronger the perspective.
    public static let distance: Float = 1600
    /// Time constant (seconds) with which the lean follows its target.
    public static let smoothing: Float = 0.09

    /// Target lean `(pitch, yaw)` for a velocity in points per second. Moving right pushes the right edge away,
    /// moving down pushes the bottom edge away, like leaning into the wind.
    public static func target(for velocity: SIMD2<Float>) -> SIMD2<Float> {
        let scaled = velocity / fullSpeed
        let length = simd_length(scaled)
        let limited = length > 1 ? scaled / length : scaled
        return SIMD2(limited.y, -limited.x) * maxAngle
    }

    /// Moves `current` towards `target` over `dt` seconds; snaps to exactly zero when the target is zero and
    /// the lean is too small to see, so the real window can take over without a jump.
    public static func follow(_ current: SIMD2<Float>, target: SIMD2<Float>, dt: Float) -> SIMD2<Float> {
        let next = current + (target - current) * (1 - exp(-max(dt, 0) / smoothing))
        if target == .zero, simd_length(next) < 0.002 { return .zero }
        return next
    }

    /// Projects a point of the window plane, rotated by `(pitch, yaw)` around `pivot`, back onto the screen.
    public static func project(_ point: SIMD2<Float>, pivot: SIMD2<Float>, angles: SIMD2<Float>) -> SIMD2<Float> {
        guard angles != .zero else { return point }
        let (pitch, yaw) = (angles.x, angles.y)
        let rel = point - pivot
        let cy = cos(yaw), sy = sin(yaw), cx = cos(pitch), sx = sin(pitch)
        let yawed = SIMD3<Float>(rel.x * cy, rel.y, -rel.x * sy)
        let z = yawed.y * sx + yawed.z * cx
        let y = yawed.y * cx - yawed.z * sx
        let scale = distance / max(distance + z, 1)
        return pivot + SIMD2(yawed.x, y) * scale
    }
}
