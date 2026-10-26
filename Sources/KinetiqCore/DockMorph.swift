// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd

/// How a minimized window travels into its icon in the Dock.
public enum DockMorphStyle: String, CaseIterable, Sendable {
    /// The window shrinks and slides into the icon, every point on a straight path.
    case morph
    /// The edge nearest the icon leads and the rest follows, narrowing into a funnel (a genie, drawn by Kinetiq).
    case genie
    /// The icon sucks the window in like jelly: it accelerates and ripples sideways on the way.
    case jellySuck

    public var title: String {
        switch self {
        case .morph: return "Dock Morph"
        case .genie: return "Genie"
        case .jellySuck: return "Jelly Suck"
        }
    }

    /// Default animation time in seconds.
    public var duration: Float {
        switch self {
        case .morph: return 0.45
        case .genie: return 0.6
        case .jellySuck: return 0.7
        }
    }
}

/// Deforms a window into the rectangle of its Dock icon over `duration` seconds.
/// Global coordinates in points with Y pointing down, like every `WindowDeformer`.
public final class DockMorphDeformer: WindowDeformer {
    public let size: SIMD2<Float>
    public let origin: SIMD2<Float>
    public let iconOrigin: SIMD2<Float>
    public let iconSize: SIMD2<Float>
    public let style: DockMorphStyle
    public let duration: Float
    public private(set) var elapsed: Float = 0

    /// Which axis the icon is mostly along (0: horizontal, 1: vertical) and whether it lies at the high end of it.
    private let axis: Int
    private let towardsHigh: Bool

    public init(windowOrigin: SIMD2<Float>, windowSize: SIMD2<Float>, iconOrigin: SIMD2<Float>, iconSize: SIMD2<Float>,
                style: DockMorphStyle, duration: Float? = nil) {
        origin = windowOrigin
        size = windowSize
        self.iconOrigin = iconOrigin
        self.iconSize = iconSize
        self.style = style
        self.duration = max(duration ?? style.duration, 0.05)
        let delta = (iconOrigin + iconSize / 2) - (windowOrigin + windowSize / 2)
        axis = abs(delta.y) >= abs(delta.x) ? 1 : 0
        towardsHigh = delta[axis] >= 0
    }

    public var progress: Float { min(max(elapsed / duration, 0), 1) }

    /// Opacity of the window: it fades out as it reaches the icon.
    public var alpha: Float {
        let t = min(max((progress - 0.8) / 0.2, 0), 1)
        return 1 - t * t * (3 - 2 * t)
    }

    public var isSettled: Bool { elapsed >= duration }

    public func step(_ dt: Float) {
        elapsed = min(elapsed + max(dt, 0), duration)
    }

    public func snapToRest() {
        elapsed = duration
    }

    public func displacement(u: Float, v: Float) -> SIMD2<Float> {
        target(u: u, v: v) - (origin + SIMD2(u * size.x, v * size.y))
    }

    /// Where the window's point `(u, v)` is at the current progress.
    public func target(u: Float, v: Float) -> SIMD2<Float> {
        let rest = origin + SIMD2(u * size.x, v * size.y)
        let inIcon = iconOrigin + SIMD2(u * iconSize.x, v * iconSize.y)
        let p = progress
        switch style {
        case .morph:
            return simd_mix(rest, inIcon, SIMD2(repeating: Self.easeInOut(p)))
        case .genie:
            // `lead` is 1 at the edge nearest the icon: it starts first, and the rest follows with a delay.
            let along = axis == 1 ? v : u
            let lead = towardsHigh ? along : 1 - along
            let gap: Float = 0.8
            let line = Self.easeInOut(min(max(p * (1 + gap) - gap * (1 - lead), 0), 1))
            // Along the travel direction the line moves at its own pace; across it, it narrows faster (the funnel).
            let pinch = pow(line, 0.7)
            var point = rest
            point[axis] = rest[axis] + (inIcon[axis] - rest[axis]) * line
            let cross = 1 - axis
            let iconCenter = iconOrigin[cross] + iconSize[cross] / 2
            let narrowed = iconCenter + ((axis == 1 ? u : v) - 0.5) * iconSize[cross]
            point[cross] = rest[cross] + (narrowed - rest[cross]) * pinch
            return point
        case .jellySuck:
            let base = simd_mix(rest, inIcon, SIMD2(repeating: Self.easeIn(p)))
            // Waves across the direction of travel, strongest in the middle of the trip and gone at both ends.
            let along = axis == 1 ? v : u
            let envelope = sin(Float.pi * p) * (1 - p)
            let wave = sin(2 * Float.pi * (2.5 * along + 3 * p)) * envelope
            var point = base
            let cross = 1 - axis
            point[cross] += wave * 0.045 * size[cross]
            return point
        }
    }

    private static func easeInOut(_ t: Float) -> Float {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func easeIn(_ t: Float) -> Float {
        t * t * (0.4 + 0.6 * t)
    }
}
