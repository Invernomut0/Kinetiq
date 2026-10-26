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
    /// The window spins down the drain: it twists around the icon while it shrinks into it.
    case whirlpool
    /// The whole window turns a full circle while it flies into the icon.
    case tornado
    /// The window first swells away from the icon like a stretched rubber band, then snaps into it.
    case rubberBand
    /// The window is flattened first, then the pancake slides into the icon.
    case pancake
    /// Like the genie, but the window folds into zigzag bands on the way, like a concertina.
    case accordion
    /// The window jumps in an arc and lands in the icon.
    case hop

    public var title: String {
        switch self {
        case .morph: return "Dock Morph"
        case .genie: return "Genie"
        case .jellySuck: return "Jelly Suck"
        case .whirlpool: return "Whirlpool"
        case .tornado: return "Tornado"
        case .rubberBand: return "Rubber Band"
        case .pancake: return "Pancake"
        case .accordion: return "Accordion"
        case .hop: return "Hop"
        }
    }

    /// Default animation time in seconds.
    public var duration: Float {
        switch self {
        case .morph: return 0.45
        case .genie: return 0.6
        case .jellySuck: return 0.7
        case .whirlpool: return 0.8
        case .tornado: return 0.8
        case .rubberBand: return 0.6
        case .pancake: return 0.6
        case .accordion: return 0.7
        case .hop: return 0.7
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
            return funnel(u: u, v: v, gap: 0.8, zigzag: 0)
        case .accordion:
            return funnel(u: u, v: v, gap: 0.5, zigzag: 0.07)
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
        case .whirlpool:
            let e = Self.easeIn(p)
            let windowCenter = origin + size / 2
            let iconCenter = iconOrigin + iconSize / 2
            let reach = max(simd_length(size / 2), 1)
            let r = min(simd_length(rest - windowCenter) / reach, 1)
            // The inside of the window turns faster than its edge, and the turn is undone just before it is in the icon.
            let settle = 1 - Self.smoothstep(0.8, 1, p)
            let angle = e * (1.5 * Float.pi + 2 * Float.pi * (1 - r)) * settle
            let moved = simd_mix(rest, inIcon, SIMD2(repeating: e))
            return iconCenter + Self.rotate(moved - iconCenter, by: angle)
        case .tornado:
            let e = Self.easeInOut(p)
            let windowCenter = origin + size / 2
            let iconCenter = iconOrigin + iconSize / 2
            // Uniform scale that makes the whole window fit in the icon.
            let endScale = min(iconSize.x / max(size.x, 1), iconSize.y / max(size.y, 1))
            let scale = 1 + (endScale - 1) * e
            let center = simd_mix(windowCenter, iconCenter, SIMD2(repeating: e))
            return center + Self.rotate((rest - windowCenter) * scale, by: 2 * Float.pi * e)
        case .rubberBand:
            // Negative at first: the window grows away from the icon, then it is released.
            return simd_mix(rest, inIcon, SIMD2(repeating: Self.easeInBack(p)))
        case .pancake:
            let center = origin + size / 2
            let flatten = Self.easeInOut(min(p / 0.45, 1))
            let slide = Self.easeInOut(min(max((p - 0.35) / 0.65, 0), 1))
            var flat = rest
            flat.y = center.y + (rest.y - center.y) * (1 - 0.92 * flatten)
            // The sides bulge a little while it is squashed.
            flat.x = center.x + (rest.x - center.x) * (1 + 0.06 * flatten * (1 - slide))
            return simd_mix(flat, inIcon, SIMD2(repeating: slide))
        case .hop:
            let e = Self.easeInOut(p)
            var point = simd_mix(rest, inIcon, SIMD2(repeating: e))
            let distance = simd_length((iconOrigin + iconSize / 2) - (origin + size / 2))
            point.y -= sin(Float.pi * e) * 0.18 * distance
            return point
        }
    }

    /// The line of the window `(u, v)` is on, for the genie and the accordion. `lead` is 1 at the edge nearest the icon:
    /// it starts first, and the rest follows with a delay of `gap`.
    private func funnel(u: Float, v: Float, gap: Float, zigzag: Float) -> SIMD2<Float> {
        let rest = origin + SIMD2(u * size.x, v * size.y)
        let inIcon = iconOrigin + SIMD2(u * iconSize.x, v * iconSize.y)
        let along = axis == 1 ? v : u
        let lead = towardsHigh ? along : 1 - along
        let line = Self.easeInOut(min(max(progress * (1 + gap) - gap * (1 - lead), 0), 1))
        // Along the travel direction the line moves at its own pace; across it, it narrows faster (the funnel).
        let pinch = pow(line, 0.7)
        var point = rest
        point[axis] = rest[axis] + (inIcon[axis] - rest[axis]) * line
        let cross = 1 - axis
        let iconCenter = iconOrigin[cross] + iconSize[cross] / 2
        let narrowed = iconCenter + ((axis == 1 ? u : v) - 0.5) * iconSize[cross]
        point[cross] = rest[cross] + (narrowed - rest[cross]) * pinch
        if zigzag > 0 {
            // Bands bend alternately to each side while they travel, and are straight again at both ends.
            point[cross] += sin(2 * Float.pi * 4 * lead) * zigzag * size[cross] * sin(Float.pi * line)
        }
        return point
    }

    private static func rotate(_ point: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let c = cos(angle), s = sin(angle)
        return SIMD2(point.x * c - point.y * s, point.x * s + point.y * c)
    }

    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func easeInBack(_ t: Float) -> Float {
        let c1: Float = 1.2
        return (c1 + 1) * t * t * t - c1 * t * t
    }

    private static func easeInOut(_ t: Float) -> Float {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func easeIn(_ t: Float) -> Float {
        t * t * (0.4 + 0.6 * t)
    }
}
