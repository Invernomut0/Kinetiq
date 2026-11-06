// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CoreGraphics

/// Reversible window dynamics in global, Y-down points. No desktop API is called here.
public struct CatalogDynamics {
    public struct Body: Equatable {
        public var frame: CGRect
        public var velocity: CGPoint
        public init(frame: CGRect, velocity: CGPoint = .zero) {
            self.frame = frame
            self.velocity = velocity
        }
    }

    public private(set) var body: Body
    public let bounds: CGRect
    public private(set) var elapsed: Double = 0
    private var remainder: Double = 0
    public static let timestep = 1.0 / 120

    public init(frame: CGRect, bounds: CGRect) {
        self.bounds = bounds
        body = Body(frame: frame)
    }

    /// Drops stalls beyond 100 ms rather than integrating an unbounded catch-up burst.
    /// Parameters are sampled by the caller from the real preset's local layer clock.
    public mutating func advance(_ seconds: Double, effect: EffectID,
                                 parameters: [String: Double], targets: [CGRect] = []) {
        guard seconds.isFinite, seconds > 0, Self.valid(bounds), Self.valid(body.frame) else { return }
        remainder += min(0.1, seconds)
        var steps = 0
        while remainder + 1e-12 >= Self.timestep, steps < 12 {
            step(effect: effect, parameters: parameters, targets: targets)
            remainder = max(0, remainder - Self.timestep)
            elapsed += Self.timestep
            steps += 1
        }
    }

    private mutating func step(effect: EffectID, parameters: [String: Double], targets: [CGRect]) {
        func value(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            let v = parameters[key] ?? fallback
            return v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : fallback
        }
        let dt = Self.timestep
        let amplitude = value("amplitude", 1, 0...2)
        let speed = value("speed", 1, 0.1...4)
        if effect == .gravity {
            body.velocity.y += value("acceleration", 980, 0...3000) * amplitude * speed * speed * dt
        } else if effect == .magnet {
            let radius = value("radius", 160, 10...600)
            let strength = value("strength", 1, 0...2) * amplitude
            let f = body.frame
            var destinations = [CGPoint(x: bounds.minX, y: f.minY),
                                CGPoint(x: bounds.maxX - f.width, y: f.minY),
                                CGPoint(x: f.minX, y: bounds.minY),
                                CGPoint(x: f.minX, y: bounds.maxY - f.height)]
            for target in targets where Self.valid(target) {
                destinations += [CGPoint(x: target.minX - f.width, y: f.minY),
                                 CGPoint(x: target.maxX, y: f.minY),
                                 CGPoint(x: f.minX, y: target.minY - f.height),
                                 CGPoint(x: f.minX, y: target.maxY)]
            }
            if let nearest = destinations.min(by: {
                hypot($0.x - f.minX, $0.y - f.minY) < hypot($1.x - f.minX, $1.y - f.minY)
            }), hypot(nearest.x - f.minX, nearest.y - f.minY) <= radius {
                body.velocity.x += (nearest.x - f.minX) * strength * 30 * speed * speed * dt
                body.velocity.y += (nearest.y - f.minY) * strength * 30 * speed * speed * dt
            }
            let damping = exp(-8 * speed * dt)
            body.velocity.x *= damping
            body.velocity.y *= damping
        } else { return }
        body.frame.origin.x += body.velocity.x * dt
        body.frame.origin.y += body.velocity.y * dt
        let restitution = effect == .gravity ? value("restitution", 0.6, 0...1) : 0
        let maxX = max(bounds.minX, bounds.maxX - body.frame.width)
        let maxY = max(bounds.minY, bounds.maxY - body.frame.height)
        if body.frame.minX < bounds.minX {
            body.frame.origin.x = bounds.minX; body.velocity.x = abs(body.velocity.x) * restitution
        } else if body.frame.minX > maxX {
            body.frame.origin.x = maxX; body.velocity.x = -abs(body.velocity.x) * restitution
        }
        if body.frame.minY < bounds.minY {
            body.frame.origin.y = bounds.minY; body.velocity.y = abs(body.velocity.y) * restitution
        } else if body.frame.minY > maxY {
            body.frame.origin.y = maxY; body.velocity.y = -abs(body.velocity.y) * restitution
        }
    }

    private static func valid(_ r: CGRect) -> Bool {
        !r.isNull && !r.isInfinite && r.width > 0 && r.height > 0
            && [r.minX, r.minY, r.maxX, r.maxY].allSatisfy(\.isFinite)
    }
}