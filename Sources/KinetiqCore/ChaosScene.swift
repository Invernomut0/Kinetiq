// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import simd

/// A saved desktop element (app window, Dock, menu bar...) with its objects cut out.
public struct ChaosWindowInput: @unchecked Sendable {
    /// Position on the screen, in points, y down.
    public var frame: CGRect
    public var extraction: UIExtraction

    public init(frame: CGRect, extraction: UIExtraction) {
        self.frame = frame
        self.extraction = extraction
    }
}

/// Everything the world and the renderer need, built from the saved desktop.
public struct ChaosScene: @unchecked Sendable {
    public var seeds: [ChaosSeed]
    /// Objects cut out of the windows; `ChaosSeed.sprite` of letters, buttons and icons indexes this list.
    public var sprites: [UIObject]
    /// Window pieces; `ChaosSeed.sprite` of a shard indexes this list.
    public var tiles: [ChaosTile]
    /// The cleaned picture of every window, in the order of `ChaosSeed.group`.
    public var pictures: [CGImage]
    public var frames: [CGRect]
}

public enum ChaosSceneBuilder {
    /// `windows` are ordered back to front.
    public static func build(windows: [ChaosWindowInput], maxTiles: Int = 1400) -> ChaosScene {
        let area = windows.reduce(CGFloat(0)) { $0 + $1.frame.width * $1.frame.height }
        let tile = ChaosTiling.tileSize(forTotalArea: area, maxTiles: maxTiles)
        var scene = ChaosScene(seeds: [], sprites: [], tiles: [], pictures: [], frames: [])
        for (group, window) in windows.enumerated() {
            let image = window.extraction.cleaned
            let sx = CGFloat(image.width) / window.frame.width, sy = CGFloat(image.height) / window.frame.height
            scene.pictures.append(image)
            scene.frames.append(window.frame)

            for t in ChaosTiling.tiles(of: image, size: window.frame.size, tile: tile) {
                let origin = SIMD2(Float(window.frame.minX), Float(window.frame.minY))
                let centroid = t.centroid
                let local = t.verts.map { $0 - centroid }
                let uvScale = SIMD2(1 / Float(window.frame.width), 1 / Float(window.frame.height))
                let polygon = ChaosPolygon(verts: local, uvOffset: centroid * uvScale, uvScale: uvScale)
                let size = (local.dropFirst().reduce(local[0]) { simd_max($0, $1) }) - (local.dropFirst().reduce(local[0]) { simd_min($0, $1) })
                scene.seeds.append(ChaosSeed(kind: .shard, center: origin + centroid, size: size, group: group, sprite: scene.tiles.count, polygon: polygon))
                scene.tiles.append(t)
            }
            for object in window.extraction.objects {
                let kind: ChaosPieceKind
                switch object.kind {
                case .glyph: kind = .glyph
                case .windowButton, .button: kind = .button
                case .icon, .dockIcon: kind = .icon
                }
                let center = SIMD2(Float(window.frame.minX + object.frame.midX), Float(window.frame.minY + object.frame.midY))
                let drawn = SIMD2(Float(CGFloat(object.pixelWidth) / sx), Float(CGFloat(object.pixelHeight) / sy))
                scene.seeds.append(ChaosSeed(kind: kind, center: center, size: drawn,
                                             bodySize: SIMD2(Float(object.frame.width), Float(object.frame.height)),
                                             group: group, sprite: scene.sprites.count, isDock: object.kind == .dockIcon))
                scene.sprites.append(object)
            }
        }
        return scene
    }
}
