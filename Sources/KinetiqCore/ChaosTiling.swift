// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import simd

/// One irregular triangle of a window picture that can break off.
public struct ChaosTile: Sendable {
    /// Corners in window-local points, y down.
    public var a: SIMD2<Float>, b: SIMD2<Float>, c: SIMD2<Float>
    /// The same corners in the picture (0...1, row 0 on top).
    public var ua: SIMD2<Float>, ub: SIMD2<Float>, uc: SIMD2<Float>

    public var centroid: SIMD2<Float> { (a + b + c) / 3 }

    public var area: Float { abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2 }
}

public enum ChaosTiling {
    /// Cuts a window picture into irregular triangles: a lattice of about `tile` points whose inner corners are moved
    /// at random and whose cells are split along a random diagonal. The border of the window stays straight and
    /// triangles side by side share their corners, so together they reproduce the picture exactly. Triangles with
    /// nothing painted in them (transparent corners, desktop layers) are left out.
    public static func tiles(of image: CGImage, size: CGSize, tile: CGFloat) -> [ChaosTile] {
        let W = image.width, H = image.height
        guard W > 0, H > 0, size.width > 0, size.height > 0, tile > 4 else { return [] }
        let cols = max(1, Int((size.width / tile).rounded())), rows = max(1, Int((size.height / tile).rounded()))

        // Alpha at a quarter of the resolution is enough to tell whether a triangle has anything in it.
        let step = 4
        let mw = max(1, (W + step - 1) / step), mh = max(1, (H + step - 1) / step)
        guard let context = CGContext(data: nil, width: mw, height: mh, bitsPerComponent: 8, bytesPerRow: mw,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return [] }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: mw, height: mh))
        let alpha = data.bindMemory(to: UInt8.self, capacity: mw * mh)
        func painted(_ lo: SIMD2<Float>, _ hi: SIMD2<Float>) -> Bool {
            let x0 = max(0, Int(lo.x) / step), x1 = min(mw, (Int(hi.x) + step) / step + 1)
            let y0 = max(0, Int(lo.y) / step), y1 = min(mh, (Int(hi.y) + step) / step + 1)
            guard x0 < x1, y0 < y1 else { return false }
            for y in y0..<y1 {
                for x in x0..<x1 where alpha[y * mw + x] > 20 { return true }
            }
            return false
        }

        // The same window always breaks along the same lines.
        var rng = SplitMix64(seed: UInt64(W) &* 73_856_093 ^ UInt64(H) &* 19_349_663 ^ UInt64(cols * 31 + rows))
        let cellW = Float(W) / Float(cols), cellH = Float(H) / Float(rows)
        var grid = [SIMD2<Float>](repeating: .zero, count: (cols + 1) * (rows + 1))
        for j in 0...rows {
            for i in 0...cols {
                var p = SIMD2(Float(i) * cellW, Float(j) * cellH)
                if i > 0, i < cols { p.x += Float.random(in: -0.34...0.34, using: &rng) * cellW }
                if j > 0, j < rows { p.y += Float.random(in: -0.34...0.34, using: &rng) * cellH }
                // Along the border the corners also slide a little, so the cracks do not all start at the same distance.
                if (j == 0 || j == rows), i > 0, i < cols { p.x += Float.random(in: -0.2...0.2, using: &rng) * cellW }
                if (i == 0 || i == cols), j > 0, j < rows { p.y += Float.random(in: -0.2...0.2, using: &rng) * cellH }
                grid[j * (cols + 1) + i] = p
            }
        }

        let toPoints = SIMD2(Float(size.width) / Float(W), Float(size.height) / Float(H))
        let toUV = SIMD2(1 / Float(W), 1 / Float(H))
        var result: [ChaosTile] = []
        func add(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>) {
            guard painted(simd_min(simd_min(p0, p1), p2), simd_max(simd_max(p0, p1), p2)) else { return }
            result.append(ChaosTile(a: p0 * toPoints, b: p1 * toPoints, c: p2 * toPoints, ua: p0 * toUV, ub: p1 * toUV, uc: p2 * toUV))
        }
        for j in 0..<rows {
            for i in 0..<cols {
                let tl = grid[j * (cols + 1) + i], tr = grid[j * (cols + 1) + i + 1]
                let bl = grid[(j + 1) * (cols + 1) + i], br = grid[(j + 1) * (cols + 1) + i + 1]
                if Bool.random(using: &rng) {
                    add(tl, tr, br); add(tl, br, bl)
                } else {
                    add(tl, tr, bl); add(tr, br, bl)
                }
            }
        }
        return result
    }

    /// Tile size in points that keeps the number of triangles of all windows under `maxTiles` (a cell makes two).
    public static func tileSize(forTotalArea area: CGFloat, maxTiles: Int, minimum: CGFloat = 56, maximum: CGFloat = 130) -> CGFloat {
        guard area > 0, maxTiles > 0 else { return minimum }
        return min(max((2 * area / CGFloat(maxTiles)).squareRoot(), minimum), maximum)
    }
}
