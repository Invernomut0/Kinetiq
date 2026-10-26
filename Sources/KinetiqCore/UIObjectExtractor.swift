// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import simd

/// What a piece cut out of a saved window is.
public enum UIObjectKind: Int, CaseIterable, Sendable {
    /// A letter (or a small run of touching letters) of some text.
    case glyph
    /// Close / minimise / zoom circle in the top-left corner of a window.
    case windowButton
    /// Wide filled control such as a push button.
    case button
    /// Squarish picture: toolbar icon, desktop icon, image.
    case icon
    /// Icon of the Dock.
    case dockIcon
}

public enum UIWindowRole: Sendable {
    case app, dock
}

/// One object cut out of a window: where it was and its picture.
public struct UIObject: @unchecked Sendable {
    public var kind: UIObjectKind
    /// Tight bounds in window-local points (y down).
    public var frame: CGRect
    /// Pixels of transparent margin around `frame` in the tile.
    public var margin: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Premultiplied RGBA8, row 0 on top.
    public var rgba: [UInt8]
}

public struct UIExtraction: @unchecked Sendable {
    public var objects: [UIObject]
    /// The window with every extracted object painted over with its background.
    public var cleaned: CGImage
}

/// Finds the letters, buttons and icons of a window picture and cuts them out. No Accessibility access is needed:
/// the background of every 32 pt tile is its most common colour, whatever differs from it is foreground, and the
/// connected foreground regions are classified by size and shape.
public enum UIObjectExtractor {
    private static let foregroundThreshold = 96

    public static func extract(from image: CGImage, size: CGSize, role: UIWindowRole = .app,
                               maxGlyphs: Int = 2500, maxOthers: Int = 400) -> UIExtraction? {
        let W = image.width, H = image.height
        guard W >= 8, H >= 8, size.width > 0, size.height > 0 else { return nil }
        let n = W * H
        let scale = CGFloat(W) / size.width

        let px = UnsafeMutablePointer<UInt8>.allocate(capacity: n * 4)
        px.initialize(repeating: 0, count: n * 4)
        defer { px.deallocate() }
        guard let context = CGContext(data: px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))

        // 1. Background of every tile and the distance of every pixel to it.
        let tile = max(16, Int((32 * scale).rounded()))
        let tx = (W + tile - 1) / tile, ty = (H + tile - 1) / tile
        var bg = [Int32](repeating: 0, count: tx * ty * 4)
        var counts = [UInt16](repeating: 0, count: 16384)
        var touched: [Int] = []
        let diff = UnsafeMutablePointer<UInt16>.allocate(capacity: n)
        defer { diff.deallocate() }
        for j in 0..<ty {
            for i in 0..<tx {
                let x0 = i * tile, x1 = min(W, x0 + tile), y0 = j * tile, y1 = min(H, y0 + tile)
                touched.removeAll(keepingCapacity: true)
                for y in y0..<y1 {
                    var o = (y * W + x0) * 4
                    for _ in x0..<x1 {
                        let key = (Int(px[o]) >> 4) << 10 | (Int(px[o + 1]) >> 4) << 6 | (Int(px[o + 2]) >> 4) << 2 | Int(px[o + 3]) >> 6
                        if counts[key] == 0 { touched.append(key) }
                        counts[key] &+= 1
                        o += 4
                    }
                }
                var best = 0, bestCount: UInt16 = 0
                for k in touched where counts[k] > bestCount { bestCount = counts[k]; best = k }
                var sum = SIMD4<Int32>(repeating: 0), c: Int32 = 0
                for y in y0..<y1 {
                    var o = (y * W + x0) * 4
                    for _ in x0..<x1 {
                        let key = (Int(px[o]) >> 4) << 10 | (Int(px[o + 1]) >> 4) << 6 | (Int(px[o + 2]) >> 4) << 2 | Int(px[o + 3]) >> 6
                        if key == best { sum &+= SIMD4(Int32(px[o]), Int32(px[o + 1]), Int32(px[o + 2]), Int32(px[o + 3])); c += 1 }
                        o += 4
                    }
                }
                for k in touched { counts[k] = 0 }
                let avg = c > 0 ? sum / c : SIMD4<Int32>(repeating: 0)
                let t = (j * tx + i) * 4
                bg[t] = avg.x; bg[t + 1] = avg.y; bg[t + 2] = avg.z; bg[t + 3] = avg.w
                for y in y0..<y1 {
                    var o = (y * W + x0) * 4
                    for x in x0..<x1 {
                        let d = abs(Int32(px[o]) - avg.x) + abs(Int32(px[o + 1]) - avg.y) + abs(Int32(px[o + 2]) - avg.z) + abs(Int32(px[o + 3]) - avg.w)
                        diff[y * W + x] = UInt16(d)
                        o += 4
                    }
                }
            }
        }
        func backgroundAt(_ x: Int, _ y: Int) -> SIMD4<Int32> {
            let t = ((y / tile) * tx + x / tile) * 4
            return SIMD4(bg[t], bg[t + 1], bg[t + 2], bg[t + 3])
        }

        // 2. Connected foreground regions (8-connectivity, union-find).
        let labels = UnsafeMutablePointer<Int32>.allocate(capacity: n)
        labels.initialize(repeating: 0, count: n)
        defer { labels.deallocate() }
        var parent: [Int32] = [0]
        parent.reserveCapacity(1 << 16)
        func find(_ a: Int32) -> Int32 {
            var a = a
            while parent[Int(a)] != a {
                parent[Int(a)] = parent[Int(parent[Int(a)])]
                a = parent[Int(a)]
            }
            return a
        }
        let threshold = UInt16(foregroundThreshold)
        for y in 0..<H {
            for x in 0..<W {
                let idx = y * W + x
                guard diff[idx] >= threshold else { continue }
                let a = x > 0 ? labels[idx - 1] : 0
                let b = (y > 0 && x > 0) ? labels[idx - W - 1] : 0
                let c = y > 0 ? labels[idx - W] : 0
                let d = (y > 0 && x + 1 < W) ? labels[idx - W + 1] : 0
                var root: Int32 = 0
                for l in [a, b, c, d] where l != 0 {
                    let r = find(l)
                    if root == 0 { root = r } else if r != root {
                        if r < root { parent[Int(root)] = r; root = r } else { parent[Int(r)] = root }
                    }
                }
                if root == 0 {
                    root = Int32(parent.count)
                    parent.append(root)
                }
                labels[idx] = root
            }
        }
        var rootIndex = [Int32](repeating: -1, count: parent.count)
        var roots: [Int32] = []
        for l in 1..<parent.count where parent[l] == Int32(l) {
            rootIndex[l] = Int32(roots.count)
            roots.append(Int32(l))
        }
        guard !roots.isEmpty else { return UIExtraction(objects: [], cleaned: image) }
        var minX = [Int32](repeating: Int32.max, count: roots.count), minY = minX
        var maxX = [Int32](repeating: -1, count: roots.count), maxY = maxX
        var area = [Int32](repeating: 0, count: roots.count)
        for y in 0..<H {
            for x in 0..<W {
                let idx = y * W + x
                guard labels[idx] != 0 else { continue }
                let r = find(labels[idx])
                labels[idx] = r
                let k = Int(rootIndex[Int(r)])
                minX[k] = min(minX[k], Int32(x)); maxX[k] = max(maxX[k], Int32(x))
                minY[k] = min(minY[k], Int32(y)); maxY[k] = max(maxY[k], Int32(y))
                area[k] += 1
            }
        }

        // 3. Classify.
        struct Candidate { var root: Int32; var kind: UIObjectKind; var x0: Int, y0: Int, x1: Int, y1: Int }
        var glyphs: [Candidate] = [], others: [Candidate] = []
        for k in roots.indices {
            let bw = Int(maxX[k] - minX[k]) + 1, bh = Int(maxY[k] - minY[k]) + 1
            let wpt = CGFloat(bw) / scale, hpt = CGFloat(bh) / scale
            guard area[k] >= 3, wpt <= 260 else { continue }
            let fill = CGFloat(area[k]) / CGFloat(bw * bh)
            let xpt = CGFloat(minX[k]) / scale, ypt = CGFloat(minY[k]) / scale
            let aspect = wpt / max(hpt, 0.01)
            var kind: UIObjectKind?
            if role == .app, xpt < 84, ypt < 46, (8...19).contains(wpt), (8...19).contains(hpt), (0.75...1.33).contains(aspect), fill >= 0.6 {
                kind = .windowButton
            } else if wpt >= 20, hpt >= 20, wpt <= 200, hpt <= 200, (0.55...1.8).contains(aspect) {
                kind = role == .dock ? .dockIcon : .icon
            } else if hpt <= 48, wpt <= 90, role == .app || hpt >= 3, fill >= 0.06 {
                kind = .glyph
            } else if (36...260).contains(wpt), (16...48).contains(hpt), fill >= 0.8 {
                kind = .button
            }
            guard let kind else { continue }
            let c = Candidate(root: roots[k], kind: kind, x0: Int(minX[k]), y0: Int(minY[k]), x1: Int(maxX[k]), y1: Int(maxY[k]))
            if kind == .glyph { glyphs.append(c) } else { others.append(c) }
        }
        func reading(_ a: Candidate, _ b: Candidate) -> Bool { (a.y0 / 24, a.x0) < (b.y0 / 24, b.x0) }
        others.sort(by: reading)
        if others.count > maxOthers { others = Array(others.prefix(maxOthers)) }
        // Letters inside a picked icon or button are part of it.
        let filled = others.filter { $0.kind != .glyph }
        glyphs = glyphs.filter { g in !filled.contains { g.x0 >= $0.x0 && g.x1 <= $0.x1 && g.y0 >= $0.y0 && g.y1 <= $0.y1 } }
        glyphs.sort(by: reading)
        if glyphs.count > 12_000 { glyphs = [] }   // noise of a photo, not text
        if glyphs.count > maxGlyphs { glyphs = Array(glyphs.prefix(maxGlyphs)) }

        // 4. Cut the sprites out and paint the objects over in a copy of the picture.
        let cleaned = UnsafeMutablePointer<UInt8>.allocate(capacity: n * 4)
        cleaned.initialize(from: px, count: n * 4)
        defer { cleaned.deallocate() }
        var objects: [UIObject] = []

        func paint(_ x: Int, _ y: Int, _ color: SIMD4<Int32>) {
            let o = (y * W + x) * 4
            cleaned[o] = UInt8(clamping: color.x); cleaned[o + 1] = UInt8(clamping: color.y)
            cleaned[o + 2] = UInt8(clamping: color.z); cleaned[o + 3] = UInt8(clamping: color.w)
        }

        for g in glyphs {
            let m = 2
            let bw = g.x1 - g.x0 + 1, bh = g.y1 - g.y0 + 1
            let tw = bw + 2 * m, th = bh + 2 * m
            let back = backgroundAt((g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2)
            var dmax: UInt16 = 0
            for y in g.y0...g.y1 { for x in g.x0...g.x1 where labels[y * W + x] == g.root { dmax = max(dmax, diff[y * W + x]) } }
            var sum = SIMD4<Int32>(repeating: 0), count: Int32 = 0
            for y in g.y0...g.y1 {
                for x in g.x0...g.x1 where labels[y * W + x] == g.root && Int(diff[y * W + x]) * 10 >= Int(dmax) * 6 {
                    let o = (y * W + x) * 4
                    sum &+= SIMD4(Int32(px[o]), Int32(px[o + 1]), Int32(px[o + 2]), Int32(px[o + 3]))
                    count += 1
                }
            }
            guard count > 0 else { continue }
            let fg = SIMD4<Float>(sum) / Float(count)
            let bgf = SIMD4<Float>(back)
            let v = fg - bgf
            let vv = simd_dot(v, v)
            guard vv > 1 else { continue }
            var rgba = [UInt8](repeating: 0, count: tw * th * 4)
            for y in max(0, g.y0 - 1)...min(H - 1, g.y1 + 1) {
                for x in max(0, g.x0 - 1)...min(W - 1, g.x1 + 1) {
                    let idx = y * W + x
                    let lab = labels[idx]
                    var take = lab == g.root
                    if !take, lab == 0, Int(diff[idx]) * 100 > Int(dmax) * 6 {
                        for dy in -1...1 {
                            for dx in -1...1 where !take {
                                let nx = x + dx, ny = y + dy
                                if nx >= 0, ny >= 0, nx < W, ny < H, labels[ny * W + nx] == g.root { take = true }
                            }
                        }
                    }
                    guard take else { continue }
                    let o = (y * W + x) * 4
                    let p = SIMD4<Float>(Float(px[o]), Float(px[o + 1]), Float(px[o + 2]), Float(px[o + 3]))
                    let a = min(1, max(0, simd_dot(p - bgf, v) / vv))
                    let out = ((y - g.y0 + m) * tw + (x - g.x0 + m)) * 4
                    rgba[out] = UInt8(min(255, fg.x * a)); rgba[out + 1] = UInt8(min(255, fg.y * a))
                    rgba[out + 2] = UInt8(min(255, fg.z * a)); rgba[out + 3] = UInt8(min(255, fg.w * a))
                    paint(x, y, back)
                }
            }
            objects.append(UIObject(kind: .glyph, frame: rect(g.x0, g.y0, g.x1, g.y1, scale), margin: m, pixelWidth: tw, pixelHeight: th, rgba: rgba))
        }

        for o in others {
            let m = 3
            let bw = o.x1 - o.x0 + 1, bh = o.y1 - o.y0 + 1
            let tw = bw + 2 * m, th = bh + 2 * m
            let back = backgroundAt((o.x0 + o.x1) / 2, (o.y0 + o.y1) / 2)
            // Exterior = what a flood from the frame around the bounds reaches without crossing the object.
            let rw = bw + 2, rh = bh + 2
            var exterior = [Bool](repeating: false, count: rw * rh)
            var stack: [Int] = []
            func push(_ cx: Int, _ cy: Int) {
                guard cx >= 0, cy >= 0, cx < rw, cy < rh, !exterior[cy * rw + cx] else { return }
                let x = o.x0 + cx - 1, y = o.y0 + cy - 1
                if x >= 0, y >= 0, x < W, y < H, labels[y * W + x] == o.root { return }
                exterior[cy * rw + cx] = true
                stack.append(cy * rw + cx)
            }
            for cx in 0..<rw { push(cx, 0); push(cx, rh - 1) }
            for cy in 0..<rh { push(0, cy); push(rw - 1, cy) }
            while let s = stack.popLast() {
                let cx = s % rw, cy = s / rw
                push(cx + 1, cy); push(cx - 1, cy); push(cx, cy + 1); push(cx, cy - 1)
            }
            var rgba = [UInt8](repeating: 0, count: tw * th * 4)
            for cy in 0..<rh {
                for cx in 0..<rw {
                    let x = o.x0 + cx - 1, y = o.y0 + cy - 1
                    guard x >= 0, y >= 0, x < W, y < H else { continue }
                    let idx = y * W + x
                    let po = idx * 4
                    let out = ((cy - 1 + m) * tw + (cx - 1 + m)) * 4
                    if !exterior[cy * rw + cx] {
                        for c in 0..<4 { rgba[out + c] = px[po + c] }
                        paint(x, y, back)
                    } else if Int(diff[idx]) * 2 >= foregroundThreshold {
                        // Soft edge: faint pixels next to the object.
                        var next = false
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !next {
                            let ax = cx + dx, ay = cy + dy
                            if ax >= 0, ay >= 0, ax < rw, ay < rh, !exterior[ay * rw + ax] { next = true }
                        }
                        if next {
                            for c in 0..<4 { rgba[out + c] = px[po + c] / 2 }
                            paint(x, y, back)
                        }
                    }
                }
            }
            objects.append(UIObject(kind: o.kind, frame: rect(o.x0, o.y0, o.x1, o.y1, scale), margin: m, pixelWidth: tw, pixelHeight: th, rgba: rgba))
        }

        let data = Data(bytes: cleaned, count: n * 4)
        guard let provider = CGDataProvider(data: data as CFData),
              let out = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                                shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIExtraction(objects: objects, cleaned: out)
    }

    private static func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ scale: CGFloat) -> CGRect {
        CGRect(x: CGFloat(x0) / scale, y: CGFloat(y0) / scale, width: CGFloat(x1 - x0 + 1) / scale, height: CGFloat(y1 - y0 + 1) / scale)
    }
}
