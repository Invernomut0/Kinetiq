// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import simd

/// A persistent sample of the window texture, in global CoreGraphics points (Y down).
public struct LiquidParticle: Sendable {
    public var position: SIMD2<Float>
    /// Points per normalized simulation second, independent of durationScale.
    public var velocity: SIMD2<Float>
    /// Original texture coordinates, with (0, 0) at the window's top-left corner.
    public var uv: SIMD2<Float>
    /// Release deadline in the same scaled seconds as LiquidWorld.elapsed.
    public var releaseTime: Float
    public var isReleased: Bool

    public init(position: SIMD2<Float>, velocity: SIMD2<Float> = .zero,
                uv: SIMD2<Float>, releaseTime: Float, isReleased: Bool = false) {
        self.position = position
        self.velocity = velocity
        self.uv = uv
        self.releaseTime = releaseTime
        self.isReleased = isReleased
    }
}

/// Bounded, deterministic particle fluid for a single disappearing desktop window.
///
/// Call on one serial executor (normally the display-link's main thread). Obstacles
/// are one-way window top edges, not solid rectangles: initially overlapping windows
/// never eject liquid. Only the screen's full bounds define the pool, not visibleFrame.
/// No particles are created or removed after initialization; UV identity is stable.
public final class LiquidWorld {
    public let windowFrame: CGRect
    public let screenBounds: CGRect
    public private(set) var particles: [LiquidParticle] = []
    /// Seconds actually simulated, scaled to match renderer release deadlines.
    public private(set) var elapsed: Float = 0
    public let spacing: Float
    public let meltDuration: Float

    /// Opacity stays at one through melting, falling and a three-second linger.
    public var alpha: Float {
        guard !particles.isEmpty else { return 0 }
        let t = Float(ticks) / 120
        let fraction = min(1, max(0, (t - fadeStart) / 3))
        return 1 - fraction * fraction * (3 - 2 * fraction)
    }

    public var isFinished: Bool { particles.isEmpty || Float(ticks) / 120 >= fadeStart + 3 }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private let scale: Float
    private let fadeStart: Float
    private let radius: Float
    private let lower: SIMD2<Float>
    private let upper: SIMD2<Float>
    private var accumulator: Double = 0
    private var ticks = 0
    private var obstacles: [CGRect] = []
    private var support: [Int] = []
    private var heads: [Cell: Int] = [:]
    private var next: [Int] = []
    private var density: [Float] = []
    private var changes: [SIMD2<Float>] = []
    private let gravity: Float = 1200

    /// Inputs must be finite, positive-area rectangles. Off-screen source portions
    /// are clipped before sampling; even enormous windows allocate at most 1500 samples.
    /// Unrepresentable desktop coordinates yield an empty, already-finished world.
    public init(windowFrame: CGRect, screenBounds: CGRect, obstacles: [CGRect], durationScale: Float = 1) {
        self.windowFrame = windowFrame
        self.screenBounds = screenBounds
        scale = durationScale.isFinite ? min(3, max(0.25, durationScale)) : 1
        meltDuration = 1.4 * scale
        let validScreen = Self.valid(screenBounds)
            && [screenBounds.minX, screenBounds.minY, screenBounds.maxX, screenBounds.maxY]
                .allSatisfy { abs($0) <= 10_000_000 }
        let clipped = validScreen && Self.valid(windowFrame) ? windowFrame.intersection(screenBounds) : .null
        let valid = validScreen && Self.valid(clipped)
        lower = valid ? SIMD2(Float(screenBounds.minX), Float(screenBounds.minY)) : .zero
        upper = valid ? SIMD2(Float(screenBounds.maxX), Float(screenBounds.maxY)) : .zero

        var columns = 0, rows = 0
        if valid {
            let target = max(8, (clipped.width * clipped.height / 1300).squareRoot())
            columns = min(1500, max(1, Int((clipped.width / target).rounded(.up))))
            rows = min(1500, max(1, Int((clipped.height / target).rounded(.up))))
            while columns * rows > 1500 {
                if columns > 1 && (rows == 1 || clipped.width / CGFloat(columns) < clipped.height / CGFloat(rows)) {
                    columns -= 1
                } else {
                    rows -= 1
                }
            }
        }
        spacing = valid ? max(0.01, Float(max(clipped.width / CGFloat(columns), clipped.height / CGFloat(rows)))) : 8
        radius = valid ? min(spacing * 0.38, Float(min(screenBounds.width, screenBounds.height)) * 0.25) : 1
        // A terminal-speed-aware fall allowance, then linger and fade. Hard upper
        // bound is 14 normalized seconds, even if a shelf prevents reaching the floor.
        let fall = valid ? min(6.6, (2 * Float(screenBounds.height) / 1200).squareRoot() + Float(screenBounds.height) / 1200) : 0
        fadeStart = min(11, 1.4 + fall + 3)

        if valid {
            particles.reserveCapacity(columns * rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = clipped.minX + (CGFloat(column) + 0.5) * clipped.width / CGFloat(columns)
                    let y = clipped.minY + (CGFloat(row) + 0.5) * clipped.height / CGFloat(rows)
                    let uv = SIMD2(Float((x - windowFrame.minX) / windowFrame.width),
                                   Float((y - windowFrame.minY) / windowFrame.height))
                    particles.append(LiquidParticle(position: SIMD2(Float(x), Float(y)), uv: uv,
                                                    releaseTime: Self.releaseFraction(u: uv.x, v: uv.y) * meltDuration))
                }
            }
        }
        support = Array(repeating: -1, count: particles.count)
        next = support
        density = Array(repeating: 0, count: particles.count)
        changes = Array(repeating: .zero, count: particles.count)
        setObstacles(obstacles)
    }

    /// Shared renderer contract: top-right first, bottom-left last. Inputs are UVs
    /// in 0...1; deliberately no easing or jitter is applied to this exact formula.
    public static func releaseFraction(u: Float, v: Float) -> Float {
        (1 - u) * 0.58 + v * 0.42
    }

    /// Refresh real window frames without projecting liquid onto newly moved tops.
    /// Identical shelves preserve support across reordering; moved/removed shelves
    /// lose it immediately. Excludes the source window and bounds work to 256 tops.
    public func setObstacles(_ obstacles: [CGRect]) {
        let previous = self.obstacles
        self.obstacles = Array(obstacles.lazy.filter {
            Self.valid($0) && $0 != self.windowFrame
                && $0.maxX > self.screenBounds.minX && $0.minX < self.screenBounds.maxX
                && $0.minY >= self.screenBounds.minY && $0.minY < self.screenBounds.maxY
        }.prefix(256))
        for i in support.indices where support[i] >= 0 {
            let old = support[i]
            support[i] = old < previous.count ? (self.obstacles.firstIndex(of: previous[old]) ?? -1) : -1
        }
    }

    /// Advances at 120 Hz in normalized time; elapsed and meltDuration remain in
    /// caller seconds. Invalid deltas are ignored. At most 0.1 normalized seconds
    /// (12 substeps) are caught up per call; excess time is dropped, not accumulated.
    /// A player should additionally enforce its own wall-clock cancellation deadline.
    public func step(_ dt: Float) {
        guard dt.isFinite, dt > 0, !isFinished else { return }
        accumulator += min(Double(dt) / Double(scale), 0.1)
        let h = 1.0 / 120.0
        var count = 0
        while accumulator + 1e-9 >= h, count < 12, !isFinished {
            accumulator = max(0, accumulator - h)
            ticks += 1
            elapsed = Float(Double(ticks) * h * Double(scale))
            simulate(Float(h))
            count += 1
        }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }

    private func cell(_ p: SIMD2<Float>) -> Cell {
        let width = max(spacing * 2.2, 0.02)
        return Cell(x: Int(floor((p.x - lower.x) / width)), y: Int(floor((p.y - lower.y) / width)))
    }

    private func buildGrid() {
        heads.removeAll(keepingCapacity: true)
        for i in particles.indices where particles[i].isReleased {
            let key = cell(particles[i].position)
            next[i] = heads[key] ?? -1
            heads[key] = i
        }
    }

    /// Stable index traversal rather than Dictionary iteration keeps runs deterministic.
    private func pairs(_ visit: (Int, Int, SIMD2<Float>, Float) -> Void) {
        let reach = spacing * 2.2
        for i in particles.indices where particles[i].isReleased {
            let key = cell(particles[i].position)
            for y in (key.y - 1)...(key.y + 1) {
                for x in (key.x - 1)...(key.x + 1) {
                    var j = heads[Cell(x: x, y: y)] ?? -1
                    while j >= 0 {
                        if j > i {
                            let delta = particles[j].position - particles[i].position
                            let squared = simd_length_squared(delta)
                            if squared < reach * reach {
                                let distance = squared.squareRoot()
                                // Deterministic separation even for exactly coincident samples.
                                let normal = distance > 0.00001 ? delta / distance : SIMD2<Float>(i.isMultiple(of: 2) ? 1 : -1, 0)
                                visit(i, j, normal, distance)
                            }
                        }
                        j = next[j]
                    }
                }
            }
        }
    }

    private func simulate(_ h: Float) {
        for i in particles.indices where !particles[i].isReleased && elapsed >= particles[i].releaseTime {
            particles[i].isReleased = true
        }
        let old = particles.map(\.position)
        for i in density.indices { density[i] = 0; changes[i] = .zero }
        buildGrid()
        let reach = spacing * 2.2
        pairs { i, j, _, distance in
            let q = 1 - distance / reach
            density[i] += q * q
            density[j] += q * q
        }
        pairs { i, j, normal, distance in
            let q = 1 - distance / reach
            // Positive density pressure and a stiff near-field prevent collapse;
            // weak attraction outside rest spacing keeps falling sheets cohesive.
            let pressure = max(0, density[i] + density[j] - 4) * 180 * q
            let repulsion = max(0, 1 - distance / spacing) * 1800
            let cohesion: Float = distance > spacing ? 110 * q : 0
            let force = normal * (pressure + repulsion - cohesion)
            let viscosity = (particles[j].velocity - particles[i].velocity) * (3.5 * q)
            changes[i] += viscosity - force
            changes[j] += force - viscosity
        }
        for i in particles.indices where particles[i].isReleased {
            var velocity = particles[i].velocity
            velocity += (bounded(changes[i], length: 4000) + SIMD2(0, gravity)) * h
            velocity *= 1 / (1 + 0.15 * h)
            if support[i] >= 0 {
                let shelf = obstacles[support[i]]
                let p = particles[i].position
                let top = Float(shelf.minY) - radius
                if p.x >= Float(shelf.minX), p.x <= Float(shelf.maxX), abs(p.y - top) <= spacing * 0.6 {
                    let left = p.x - Float(shelf.minX), right = Float(shelf.maxX) - p.x
                    let direction: Float = left < right ? -1 : 1
                    // A supported sheet drains to the nearest edge, rather than
                    // bouncing or remaining pinned by viscosity on a wide shelf.
                    let speed = max(100, min(650, min(left, right) * 1.8))
                    velocity.x += (direction * speed - velocity.x) * min(1, 8 * h)
                    velocity.y = min(0, velocity.y)
                } else {
                    support[i] = -1
                }
            }
            particles[i].velocity = bounded(velocity, length: 1200)
            particles[i].position += particles[i].velocity * h
            collide(i, from: old[i])
        }
        // Position-based density relaxation maintains finite pool volume. Corrections
        // do not become rebound velocities; liquid loses normal momentum on impact.
        for _ in 0..<2 {
            for i in changes.indices { changes[i] = .zero }
            buildGrid()
            pairs { i, j, normal, distance in
                let overlap = spacing * 0.82 - distance
                if overlap > 0 {
                    var separation = normal
                    let floor = upper.y - radius
                    if abs(normal.y) < 0.05,
                       particles[i].position.y > floor - spacing * 0.05,
                       particles[j].position.y > floor - spacing * 0.05 {
                        // A perfectly coplanar, compressed floor row has no vertical
                        // pressure gradient. Regularize that degenerate constraint
                        // deterministically so excess volume can form a second layer.
                        separation = simd_normalize(normal + SIMD2(0, i.isMultiple(of: 2) ? 0.65 : -0.65))
                    }
                    let correction = separation * min(spacing * 0.16, overlap * 0.24)
                    changes[i] -= correction
                    changes[j] += correction
                }
            }
            for i in particles.indices where particles[i].isReleased {
                particles[i].position += bounded(changes[i], length: spacing * 0.35)
                collide(i, from: old[i])
            }
        }
    }

    private func bounded(_ value: SIMD2<Float>, length: Float) -> SIMD2<Float> {
        let squared = simd_length_squared(value)
        return squared > length * length ? value * (length / squared.squareRoot()) : value
    }

    /// Sweeps against tops in vertical order, using X at the crossing, so a fast
    /// diagonal drop cannot tunnel through a narrow shelf. No side/bottom ejection.
    private func collide(_ i: Int, from old: SIMD2<Float>) {
        var p = particles[i].position
        var hit = -1
        var hitY = Float.greatestFiniteMagnitude
        for (index, rect) in obstacles.enumerated() {
            let top = Float(rect.minY) - radius
            guard old.y <= top + 0.001, p.y >= top, p.y > old.y else { continue }
            let fraction = min(1, max(0, (top - old.y) / (p.y - old.y)))
            let x = old.x + (p.x - old.x) * fraction
            // Test the impact point, not the end point: a narrow shelf may already
            // have been crossed horizontally by the end of this substep.
            guard x >= Float(rect.minX), x <= Float(rect.maxX), top < hitY else { continue }
            hit = index
            hitY = top
        }
        if hit >= 0 {
            p.y = hitY
            particles[i].velocity.y = min(0, particles[i].velocity.y)
            let rect = obstacles[hit]
            // Preserve horizontal travel; once beyond the edge, free fall resumes
            // next tick without pinning or teleporting X back onto the window.
            support[i] = p.x >= Float(rect.minX) && p.x <= Float(rect.maxX) ? hit : -1
        } else if support[i] >= 0 {
            let rect = obstacles[support[i]]
            let top = Float(rect.minY) - radius
            if p.x < Float(rect.minX) || p.x > Float(rect.maxX) || p.y < top - spacing * 0.6 {
                support[i] = -1
            } else if p.y > top, old.y <= top + 0.001 {
                p.y = top
                particles[i].velocity.y = min(0, particles[i].velocity.y)
            }
        }
        let floor = upper.y - radius
        if p.y >= floor {
            p.y = floor
            particles[i].velocity.y = min(0, particles[i].velocity.y)
            particles[i].velocity.x *= 0.985
            support[i] = -1
        }
        let minX = lower.x + radius, maxX = upper.x - radius
        if p.x < minX { p.x = minX; particles[i].velocity.x = max(0, particles[i].velocity.x) }
        if p.x > maxX { p.x = maxX; particles[i].velocity.x = min(0, particles[i].velocity.x) }
        p.y = max(lower.y + radius, p.y)
        particles[i].position = p
    }
}