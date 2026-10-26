// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import simd

/// One convex chunk of a window picture that can break off.
public struct ChaosTile: Sendable {
    /// Corners in window-local points, y down.
    public var verts: [SIMD2<Float>]

    public var centroid: SIMD2<Float> { ChaosGeometry.centroid(verts) }
    public var area: Float { ChaosGeometry.area(verts) }
}

public enum ChaosTiling {
    /// Cuts a window picture into irregular convex chunks: the Voronoi cells of a jittered grid of points, which gives
    /// four to seven sides of different lengths and angles instead of squares or triangles. The border of the window
    /// stays straight and chunks side by side share their edges, so together they reproduce the picture exactly.
    /// Chunks with nothing painted in them (transparent corners, desktop layers) are left out.
    public static func tiles(of image: CGImage, size: CGSize, tile: CGFloat) -> [ChaosTile] {
        let W = image.width, H = image.height
        guard W > 0, H > 0, size.width > 0, size.height > 0, tile > 4 else { return [] }
        let cols = max(1, Int((size.width / tile).rounded())), rows = max(1, Int((size.height / tile).rounded()))

        // Alpha at a quarter of the resolution is enough to tell whether a chunk has anything in it.
        let step = 4
        let mw = max(1, (W + step - 1) / step), mh = max(1, (H + step - 1) / step)
        guard let context = CGContext(data: nil, width: mw, height: mh, bitsPerComponent: 8, bytesPerRow: mw,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return [] }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: mw, height: mh))
        let alpha = data.bindMemory(to: UInt8.self, capacity: mw * mh)
        let toPixels = SIMD2(Float(W) / Float(size.width), Float(H) / Float(size.height))
        func painted(_ lo: SIMD2<Float>, _ hi: SIMD2<Float>) -> Bool {
            let x0 = max(0, Int(lo.x * toPixels.x) / step), x1 = min(mw, (Int(hi.x * toPixels.x) + step) / step + 1)
            let y0 = max(0, Int(lo.y * toPixels.y) / step), y1 = min(mh, (Int(hi.y * toPixels.y) + step) / step + 1)
            guard x0 < x1, y0 < y1 else { return false }
            for y in y0..<y1 {
                for x in x0..<x1 where alpha[y * mw + x] > 20 { return true }
            }
            return false
        }

        // The same window always breaks along the same lines.
        var rng = SplitMix64(seed: UInt64(W) &* 73_856_093 ^ UInt64(H) &* 19_349_663 ^ UInt64(cols * 31 + rows))
        let width = Float(size.width), height = Float(size.height)
        let cellW = width / Float(cols), cellH = height / Float(rows)
        var sites = [SIMD2<Float>](repeating: .zero, count: cols * rows)
        for j in 0..<rows {
            for i in 0..<cols {
                sites[j * cols + i] = SIMD2((Float(i) + 0.5 + Float.random(in: -0.45...0.45, using: &rng)) * cellW,
                                            (Float(j) + 0.5 + Float.random(in: -0.45...0.45, using: &rng)) * cellH)
            }
        }

        let window = [SIMD2<Float>(0, 0), SIMD2(width, 0), SIMD2(width, height), SIMD2(0, height)]
        var result: [ChaosTile] = []
        for j in 0..<rows {
            for i in 0..<cols {
                // Sites farther than two cells away cannot touch this cell.
                var near: [SIMD2<Float>] = [sites[j * cols + i]]
                for dj in -2...2 {
                    for di in -2...2 where (di != 0 || dj != 0) && i + di >= 0 && i + di < cols && j + dj >= 0 && j + dj < rows {
                        near.append(sites[(j + dj) * cols + i + di])
                    }
                }
                let cell = ChaosGeometry.cell(of: 0, in: near, bounds: window)
                guard cell.count >= 3, ChaosGeometry.area(cell) > 4 else { continue }
                let lo = cell.dropFirst().reduce(cell[0]) { simd_min($0, $1) }, hi = cell.dropFirst().reduce(cell[0]) { simd_max($0, $1) }
                if painted(lo, hi) { result.append(ChaosTile(verts: cell)) }
            }
        }
        return result
    }

    /// Tile size in points that keeps the number of chunks of all windows under `maxTiles`.
    public static func tileSize(forTotalArea area: CGFloat, maxTiles: Int, minimum: CGFloat = 56, maximum: CGFloat = 130) -> CGFloat {
        guard area > 0, maxTiles > 0 else { return minimum }
        return min(max((area / CGFloat(maxTiles)).squareRoot(), minimum), maximum)
    }
}
