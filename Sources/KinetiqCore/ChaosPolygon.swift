// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import simd

/// A convex piece of a window picture. Corners are relative to the piece's own origin (its centroid), so the piece
/// can be moved and turned; the picture coordinate of a corner is `uvOffset + corner * uvScale`.
public struct ChaosPolygon: Sendable {
    public var verts: [SIMD2<Float>]
    public var uvOffset: SIMD2<Float>
    public var uvScale: SIMD2<Float>

    public init(verts: [SIMD2<Float>], uvOffset: SIMD2<Float>, uvScale: SIMD2<Float>) {
        self.verts = verts
        self.uvOffset = uvOffset
        self.uvScale = uvScale
    }

    public func uv(_ v: SIMD2<Float>) -> SIMD2<Float> { uvOffset + v * uvScale }

    public var area: Float { ChaosGeometry.area(verts) }

    /// Average distance of the corners from the origin.
    public var meanRadius: Float {
        verts.isEmpty ? 0 : verts.reduce(0) { $0 + simd_length($1) } / Float(verts.count)
    }

    public var boundsMin: SIMD2<Float> { verts.dropFirst().reduce(verts.first ?? .zero) { simd_min($0, $1) } }
    public var boundsMax: SIMD2<Float> { verts.dropFirst().reduce(verts.first ?? .zero) { simd_max($0, $1) } }

    /// Whether a point (relative to the origin of the piece) lies inside.
    public func contains(_ p: SIMD2<Float>) -> Bool { ChaosGeometry.contains(verts, p) }
}

/// Plane geometry of convex polygons, used to cut windows into pieces and pieces into fragments.
public enum ChaosGeometry {
    public static func area(_ p: [SIMD2<Float>]) -> Float {
        guard p.count >= 3 else { return 0 }
        var sum: Float = 0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    public static func centroid(_ p: [SIMD2<Float>]) -> SIMD2<Float> {
        var twiceArea: Float = 0
        var c = SIMD2<Float>(0, 0)
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            let cross = a.x * b.y - b.x * a.y
            twiceArea += cross
            c += (a + b) * cross
        }
        guard abs(twiceArea) > 1e-6 else { return p.reduce(.zero, +) / Float(max(p.count, 1)) }
        return c / (3 * twiceArea)
    }

    public static func contains(_ p: [SIMD2<Float>], _ q: SIMD2<Float>) -> Bool {
        var negative = false, positive = false
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            let cross = (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x)
            if cross < 0 { negative = true } else if cross > 0 { positive = true }
            if negative && positive { return false }
        }
        return true
    }

    /// The part of the convex polygon that is closer to `site` than to `other`.
    public static func clip(_ p: [SIMD2<Float>], site: SIMD2<Float>, other: SIMD2<Float>) -> [SIMD2<Float>] {
        let mid = (site + other) / 2, n = other - site
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(p.count + 1)
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            let da = simd_dot(a - mid, n), db = simd_dot(b - mid, n)
            if da <= 0 { out.append(a) }
            if (da < 0 && db > 0) || (da > 0 && db < 0) { out.append(a + (b - a) * (da / (da - db))) }
        }
        return out
    }

    /// The part of the segment `a`-`b` that lies inside the convex polygon, or nil when it does not touch it.
    public static func clipSegment(_ a: SIMD2<Float>, _ b: SIMD2<Float>, to polygon: [SIMD2<Float>]) -> (SIMD2<Float>, SIMD2<Float>)? {
        guard polygon.count >= 3 else { return nil }
        var signedArea: Float = 0
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            signedArea += p.x * q.y - q.x * p.y
        }
        let orientation: Float = signedArea >= 0 ? 1 : -1
        var t0: Float = 0, t1: Float = 1
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            let e = q - p
            let fa = orientation * (e.x * (a.y - p.y) - e.y * (a.x - p.x))
            let fb = orientation * (e.x * (b.y - p.y) - e.y * (b.x - p.x))
            if fa < 0, fb < 0 { return nil }
            if fa < 0 { t0 = max(t0, fa / (fa - fb)) } else if fb < 0 { t1 = min(t1, fa / (fa - fb)) }
            if t0 >= t1 { return nil }
        }
        return (a + (b - a) * t0, a + (b - a) * t1)
    }

    /// The Voronoi cell of `sites[index]` inside the convex polygon `bounds`.
    public static func cell(of index: Int, in sites: [SIMD2<Float>], bounds: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var cell = bounds
        for j in sites.indices where j != index {
            cell = clip(cell, site: sites[index], other: sites[j])
            if cell.count < 3 { return [] }
        }
        return cell
    }
}
