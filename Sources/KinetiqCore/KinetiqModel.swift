// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Port of the Compiz wobbly model (plugins/wobbly.c), as used by the GNOME extension
// "Compiz windows effect" by Mauro Pepe (src/effects/wobbly_model.js). The original code is
// distributed under the following notice, which is also reproduced in NOTICE:

/*
 * Copyright © 2005 Novell, Inc.
 * Copyright © 2022 Mauro Pepe
 *
 * Permission to use, copy, modify, distribute, and sell this software
 * and its documentation for any purpose is hereby granted without
 * fee, provided that the above copyright notice appear in all copies
 * and that both that copyright notice and this permission notice
 * appear in supporting documentation, and that the name of
 * Novell, Inc. not be used in advertising or publicity pertaining to
 * distribution of the software without specific, written prior permission.
 * Novell, Inc. makes no representations about the suitability of this
 * software for any purpose. It is provided "as is" without express or
 * implied warranty.
 *
 * NOVELL, INC. DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN
 * NO EVENT SHALL NOVELL, INC. BE LIABLE FOR ANY SPECIAL, INDIRECT OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
 * OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
 * NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
 * WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * Author: David Reveman <davidr@novell.com>
 *         Scott Moreau <oreaus@gmail.com>
 *         Mauro Pepe <https://github.com/hermes83/compiz-windows-effect>
 *
 * Spring model implemented by Kristian Hogsberg.
 */
import Foundation
import simd

/// The same parameters and ranges as the GNOME extension.
public struct KinetiqSettings: Equatable, Sendable {
    /// 1…10. Damping: how hard it is for the window to move relative to the world.
    public var friction: Float
    /// 1…10. Stiffness of the springs between nodes.
    public var spring: Float
    /// 2…40. Divides simulation time: higher means slower and more jelly-like.
    public var speedup: Float
    /// 20…80. Used as `100 - mass`, just like GNOME.
    public var mass: Float

    public init(friction: Float, spring: Float, speedup: Float, mass: Float) {
        self.friction = friction
        self.spring = spring
        self.speedup = speedup
        self.mass = mass
    }

    public static let subtle = KinetiqSettings(friction: 1.5, spring: 1.0, speedup: 6, mass: 80)
    public static let realistic = KinetiqSettings(friction: 3.5, spring: 3.8, speedup: 12, mass: 70)
    public static let exaggerated = KinetiqSettings(friction: 5.0, spring: 4.2, speedup: 15, mass: 50)
    public static let extreme = KinetiqSettings(friction: 7.0, spring: 5.5, speedup: 19, mass: 25)

    /// GNOME runs `floor(ms / speedup) + 1` steps per frame. At 60 Hz, with normal frame jitter, that
    /// averages `1000 / speedup + 30` steps per second. We use it as a fixed rate so the result doesn't
    /// depend on the display refresh rate (120 Hz ProMotion would otherwise feel different).
    public var stepsPerSecond: Float { 1000 / speedup + 30 }
}

public final class KinetiqModel: WindowDeformer {
    public static let gridWidth = 4
    public static let gridHeight = 4
    private static let intensity: Float = 0.8

    private struct Spring {
        let a: Int
        let b: Int
        let offset: SIMD2<Float>
    }

    public let size: SIMD2<Float>
    public private(set) var origin: SIMD2<Float>
    public private(set) var positions: [SIMD2<Float>]
    public private(set) var isGrabbed = false
    /// Same as Compiz: there is movement while any node receives a force greater than 1.
    public private(set) var movement = false

    private var velocities: [SIMD2<Float>]
    private var forces: [SIMD2<Float>]
    private var immobile: [Bool]
    private let springs: [Spring]
    private var friction: Float
    private let springK: Float
    private let mass: Float
    private let stepsPerSecond: Float
    private var accumulator: Float = 0
    private var anchor: Int?
    private var lastGrabPoint = SIMD2<Float>.zero
    private var glideVelocity = SIMD2<Float>.zero
    /// Current speed of the window while it glides (zero otherwise), in points per second.
    public var glideSpeed: SIMD2<Float> { isGliding ? glideVelocity : .zero }
    private var glideBounds: (min: SIMD2<Float>, max: SIMD2<Float>)?
    /// The window keeps travelling after a fast release, bouncing off the bounds.
    public private(set) var isGliding = false
    /// How fast a glide loses speed (1/s) and how much speed is kept when bouncing off a bound.
    private static let glideDamping: Float = 3.2
    private static let glideRestitution: Float = 0.6
    private static let glideStopSpeed: Float = 30
    public init(size: SIMD2<Float>, origin: SIMD2<Float>, settings: KinetiqSettings = .realistic) {
        self.size = size
        self.origin = origin
        friction = settings.friction
        springK = settings.spring * 0.5
        mass = 100 - settings.mass
        stepsPerSecond = settings.stepsPerSecond

        let gw = Self.gridWidth
        let gh = Self.gridHeight
        let hpad = size.x / Float(gw - 1)
        let vpad = size.y / Float(gh - 1)

        var positions: [SIMD2<Float>] = []
        var springs: [Spring] = []
        for gy in 0..<gh {
            for gx in 0..<gw {
                let i = gy * gw + gx
                positions.append(origin + SIMD2(Float(gx) * hpad, Float(gy) * vpad))
                if gx > 0 { springs.append(Spring(a: i - 1, b: i, offset: SIMD2(hpad, 0))) }
                if gy > 0 { springs.append(Spring(a: i - gw, b: i, offset: SIMD2(0, vpad))) }
            }
        }
        self.positions = positions
        self.springs = springs
        velocities = Array(repeating: .zero, count: positions.count)
        forces = Array(repeating: .zero, count: positions.count)
        immobile = Array(repeating: false, count: positions.count)
    }

    // MARK: - Interaction

    /// Manhattan distance, iterating from last to first like the original (this decides ties).
    private func nearestObject(_ point: SIMD2<Float>) -> Int {
        var best = positions.count - 1
        var bestDistance: Float = -1
        for i in stride(from: positions.count - 1, through: 0, by: -1) {
            let d = abs(positions[i].x - point.x) + abs(positions[i].y - point.y)
            if bestDistance < 0 || d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return best
    }

    /// Pins the node closest to the cursor; from then on it moves with it.
    public func grab(at point: SIMD2<Float>) {
        if let anchor { immobile[anchor] = false }
        let a = nearestObject(point)
        anchor = a
        immobile[a] = true
        velocities[a] = .zero
        lastGrabPoint = point
        isGrabbed = true
        isGliding = false
    }

    public func moveGrab(to point: SIMD2<Float>, origin: SIMD2<Float>) {
        guard let anchor else { return }
        positions[anchor] += point - lastGrabPoint
        lastGrabPoint = point
        self.origin = origin
    }

    /// As in GNOME, the grabbed node stays pinned and the rest finishes wobbling around it.
    /// If the final destination is adjusted (e.g. below the menu bar), the node shifts with it.
    public func release(origin newOrigin: SIMD2<Float>) {
        if let anchor { positions[anchor] += newOrigin - origin }
        origin = newOrigin
        isGrabbed = false
    }

    /// Lets go of the grabbed node and keeps the window moving at `velocity` (points per second) after a fast release.
    /// `bounds` limits where `origin` may go (nil: free); the window bounces off them and loses speed over time.
    public func fling(velocity: SIMD2<Float>, bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?) {
        if let anchor { immobile[anchor] = false }
        anchor = nil
        isGrabbed = false
        glideVelocity = velocity
        glideBounds = bounds
        isGliding = simd_length(velocity) > Self.glideStopSpeed
    }

    private func advanceGlide(_ dt: Float) {
        var velocity = glideVelocity
        var newOrigin = origin + velocity * dt
        if let bounds = glideBounds {
            for axis in 0..<2 {
                // A bound only counts if the window fits between them on that axis.
                guard bounds.max[axis] >= bounds.min[axis] else { continue }
                let below = newOrigin[axis] < bounds.min[axis], above = newOrigin[axis] > bounds.max[axis]
                guard below || above else { continue }
                newOrigin[axis] = below ? bounds.min[axis] : bounds.max[axis]
                let incoming = velocity[axis]
                velocity[axis] = -incoming * Self.glideRestitution
                squash(axis: axis, towards: below ? -1 : 1, speed: abs(incoming))
            }
        }
        velocity *= exp(-Self.glideDamping * dt)
        let delta = newOrigin - origin
        for i in positions.indices { positions[i] += delta }
        origin = newOrigin
        glideVelocity = velocity
        if simd_length(velocity) < Self.glideStopSpeed { isGliding = false }
    }

    /// Hitting a bound: the nodes far from it keep going for a moment and the near ones give way, so the window
    /// squashes like jelly. The impulses add up to zero: nothing but the origin may carry the window away.
    private func squash(axis: Int, towards side: Float, speed: Float) {
        let impulse = speed / stepsPerSecond * 0.6
        for i in positions.indices {
            let column = Float(axis == 0 ? i % Self.gridWidth : i / Self.gridWidth) / Float(Self.gridWidth - 1)
            let distance = side < 0 ? column : 1 - column
            velocities[i][axis] += side * impulse * (distance - 0.5)
        }
    }

    /// Maximize effect: corners pinned and an inward kick on their neighbours.
    public func maximize() {
        let w = size.x
        let h = size.y
        let corners = [
            nearestObject(origin), nearestObject(origin + SIMD2(w, 0)),
            nearestObject(origin + SIMD2(0, h)), nearestObject(origin + SIMD2(w, h)),
        ]
        anchor = nil
        corners.forEach { immobile[$0] = true }
        friction = min(friction * 2, 10)
        for spring in springs {
            if let corner = corners.first(where: { $0 == spring.a || $0 == spring.b }) {
                kick(spring.a == corner ? spring.b : spring.a, spring.offset)
            }
        }
        _ = singleStep()
    }

    /// Unmaximize effect: center pinned and an inward kick on its neighbours.
    public func unmaximize() {
        let center = nearestObject(origin + size / 2)
        anchor = nil
        immobile[center] = true
        friction = min(friction * 2, 10)
        for spring in springs where spring.a == center || spring.b == center {
            kick(spring.a == center ? spring.b : spring.a, spring.offset)
        }
        _ = singleStep()
    }

    private func kick(_ index: Int, _ offset: SIMD2<Float>) {
        velocities[index] -= offset * Self.intensity
    }

    // MARK: - Simulation

    public func step(_ dt: Float) {
        if isGliding { advanceGlide(min(max(dt, 0), 1.0 / 15.0)) }
        accumulator += min(max(dt, 0), 1.0 / 15.0) * stepsPerSecond
        guard accumulator >= 1 else { return }
        var moving = false
        while accumulator >= 1 {
            moving = singleStep() || moving
            accumulator -= 1
        }
        movement = moving
    }

    private func singleStep() -> Bool {
        for s in springs {
            let f = springK * (positions[s.b] - positions[s.a] - s.offset)
            forces[s.a] += f
            forces[s.b] -= f
        }
        var moving = false
        for i in positions.indices {
            if !immobile[i] {
                forces[i] -= friction * velocities[i]
                velocities[i] += forces[i] / mass
                positions[i] += velocities[i]
                moving = moving || abs(forces[i].x) > 1 || abs(forces[i].y) > 1
            }
            forces[i] = .zero
        }
        movement = moving
        return moving
    }

    /// Compiz stops as soon as no force exceeds 1, but at that point a few points of deformation are
    /// left and vanish abruptly. We keep going until every node is within half a point of rest.
    public var isSettled: Bool {
        guard !isGrabbed, !isGliding, !movement else { return false }
        return positions.indices.allSatisfy { simd_length(positions[$0] - restPosition($0)) < 0.5 }
    }

    public func snapToRest() {
        isGliding = false
        for i in positions.indices {
            positions[i] = restPosition(i)
            velocities[i] = .zero
        }
        movement = false
    }

    private func restPosition(_ index: Int) -> SIMD2<Float> {
        let gx = index % Self.gridWidth
        let gy = index / Self.gridWidth
        return origin + SIMD2(Float(gx) * size.x / Float(Self.gridWidth - 1), Float(gy) * size.y / Float(Self.gridHeight - 1))
    }

    // MARK: - Sampling

    /// Bicubic Bézier surface with the 16 nodes as control points (like the extension).
    public func displacement(u: Float, v: Float) -> SIMD2<Float> {
        let bu = bernstein(u)
        let bv = bernstein(v)
        var p = SIMD2<Float>.zero
        for j in 0..<4 {
            for i in 0..<4 {
                p += (bv[j] * bu[i]) * positions[j * 4 + i]
            }
        }
        return p - (origin + SIMD2(u * size.x, v * size.y))
    }
}

@inline(__always)
private func bernstein(_ t: Float) -> SIMD4<Float> {
    let s = 1 - t
    return SIMD4(s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t)
}
