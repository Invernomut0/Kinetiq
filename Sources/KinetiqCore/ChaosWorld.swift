// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import simd

/// What a piece of the saved desktop is.
public enum ChaosPieceKind: Int, Sendable {
    /// A letter (or a few touching letters).
    case glyph
    /// Window button or push button: it blinks red and explodes.
    case button
    /// Toolbar, desktop or Dock icon.
    case icon
    /// A tile of the window picture (the window with its objects cut out).
    case shard
}

public enum ChaosEvent: CaseIterable, Sendable {
    /// A blast: window pieces break apart, letters and icons are thrown away, buttons nearby chain-explode.
    case bomb
    /// Letters of a few lines (or around a point) come loose and fall.
    case letterShed
    /// A button (or an icon) blinks red and explodes.
    case buttonBlast
    /// A crack runs through the window and pieces of it fall off.
    case shardCrumble
    /// The desktop shakes: loose pieces hop and some more come off.
    case quake
    /// A nuclear blast with a mushroom cloud: once per session, now and then.
    case nuke

    fileprivate var weight: Float {
        switch self {
        case .bomb: return 3
        case .letterShed: return 4
        case .buttonBlast: return 2
        case .shardCrumble: return 3
        case .quake: return 0.7
        case .nuke: return 0   // decided by the world: rare, and only once
        }
    }
}

/// Values the user can tune.
public struct ChaosSettings: Equatable, Sendable {
    public static let intervalRange: ClosedRange<Double> = 100...5000
    public static let lifetimeRange: ClosedRange<Double> = 3...120
    public static let intensityRange: ClosedRange<Double> = 0.5...2.5
    public static let speedRange: ClosedRange<Double> = 0.2...1.5

    /// Milliseconds between two events.
    public var eventInterval: Double
    /// Seconds a loose piece stays on the screen before it fades away.
    public var lifetime: Double
    /// Strength and radius of the blasts.
    public var intensity: Double
    /// 0 = a different run every time.
    public var seed: UInt64
    /// Speed of the simulation; below 1 everything moves in slow motion.
    public var speed: Double

    public init(eventInterval: Double = 1500, lifetime: Double = 15, intensity: Double = 1, seed: UInt64 = 0, speed: Double = 0.55) {
        self.eventInterval = min(max(eventInterval, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
        self.lifetime = min(max(lifetime, Self.lifetimeRange.lowerBound), Self.lifetimeRange.upperBound)
        self.intensity = min(max(intensity, Self.intensityRange.lowerBound), Self.intensityRange.upperBound)
        self.seed = seed
        self.speed = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    }
}

public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct ChaosPuff: Sendable {
    public enum Kind: Sendable { case smoke, flame, spark, dust, mote }
    public var pos: SIMD2<Float>
    public var vel: SIMD2<Float>
    public var size: Float
    public var growth: Float
    public var age: Float
    public var life: Float
    public var kind: Kind
}

public struct ChaosBody: Sendable {
    public enum State: Sendable {
        /// Still part of the desktop picture.
        case attached
        /// Will come loose when its timer runs out.
        case pending
        /// Blinking, about to explode.
        case fuse
        /// Simulated by the physics.
        case loose
        /// Removed (exploded, split or faded away).
        case gone
    }

    public var kind: ChaosPieceKind
    /// Index into the sprite atlas (glyph, button, icon) or the tile list of the window (shard).
    public var sprite: Int
    /// Window the piece came from, back to front.
    public var group: Int
    public var pos: SIMD2<Float>
    /// Drawn size in points (the bounding box for a shard).
    public var size: SIMD2<Float>
    /// Index into `ChaosWorld.polygons` for a shard, -1 otherwise.
    public var polygon: Int32 = -1
    public var vel = SIMD2<Float>(0, 0)
    public var angle: Float = 0
    public var angVel: Float = 0
    public var radius: Float
    public var invMass: Float
    public var restitution: Float
    public var friction: Float
    public var home: SIMD2<Float>
    public var state = State.attached
    public var timer: Float = 0
    public var age: Float = 0
    public var asleep = false
    var sleepTimer: Float = 0
    var grounded = false
    public var alpha: Float = 1
    public var scale: Float = 1
    /// Colour and amount blended over the sprite.
    public var tint = SIMD4<Float>(0, 0, 0, 0)
    public var flash: Float = 0
    public var isChild = false
    /// Charred along its edges (0...1) and the glow of those edges while they are still hot (0...1).
    public var burn: Float = 0
    public var heat: Float = 0
    /// Index into `ChaosWorld.crackSets`, -1 when the piece has no cracks.
    public var crack: Int32 = -1
    /// An icon of the Dock: its explosion is much stronger.
    public var isDock = false
    var shocked = false

    var invInertia: Float { invMass == 0 ? 0 : 2 * invMass / max(radius * radius * scale * scale, 1) }
    var effectiveRadius: Float { radius * scale }
}

/// Where each piece of the saved desktop sits.
public struct ChaosSeed: Sendable {
    public var kind: ChaosPieceKind
    /// Centre in screen points (y down).
    public var center: SIMD2<Float>
    /// Drawn size in points.
    public var size: SIMD2<Float>
    /// Size of the object itself, without the transparent margin of its sprite.
    public var bodySize: SIMD2<Float>
    public var group: Int
    public var sprite: Int
    /// Outline of a shard (corners relative to `center`); nil for letters, buttons and icons.
    public var polygon: ChaosPolygon?
    public var isDock = false

    public init(kind: ChaosPieceKind, center: SIMD2<Float>, size: SIMD2<Float>, bodySize: SIMD2<Float>? = nil, group: Int, sprite: Int,
                polygon: ChaosPolygon? = nil, isDock: Bool = false) {
        self.kind = kind
        self.center = center
        self.size = size
        self.bodySize = bodySize ?? size
        self.group = group
        self.sprite = sprite
        self.polygon = polygon
        self.isDock = isDock
    }
}

/// The saved desktop falling apart: every few hundred milliseconds something happens (a blast, a shower of
/// letters, a button that explodes, a crack in a window) and the pieces that come loose fall, bounce, pile up at the
/// bottom of the screen and fade away after a while. Circle physics at 120 Hz with stacking, rolling friction and sleeping.
public final class ChaosWorld {
    public let size: SIMD2<Float>
    public let settings: ChaosSettings
    public private(set) var bodies: [ChaosBody] = []
    /// Outlines of the shards; `ChaosBody.polygon` indexes this list.
    public private(set) var polygons: [ChaosPolygon] = []
    private var originalPolygonCount = 0
    public private(set) var puffs: [ChaosPuff] = []
    public private(set) var time: Float = 0
    public private(set) var eventCount = 0
    public private(set) var lastEvent: ChaosEvent?
    /// Share of the original pieces still in place (0...1).
    public private(set) var intactFraction: Float = 1
    public private(set) var looseCount = 0
    /// The reach of the biggest blast so far, in points.
    public private(set) var largestBlastRadius: Float = 0
    /// Runs an event every `settings.eventInterval`; off when the events are triggered by hand.
    public var automaticEvents = true
    /// Number of pieces that came with the desktop; the ones after them are fragments.
    public let originalCount: Int

    public static let maxPuffs = 3500
    /// Upper bound of `bodies.count`: the original pieces plus room for fragments.
    public let maxBodies: Int
    /// More loose pieces than this fade away faster.
    static let comfortableLoose = 1200

    var rng: SplitMix64
    private let gravity: Float = 1800
    private let drag: Float = 0.05
    private var accumulator: Float = 0
    private var nextEvent: Float
    private var lastCompaction: Float = 0
    private var lastFragmentCleanup: Float = 0
    private var lastQuake: Float = -10
    private var wakePoints: [SIMD2<Float>] = []

    /// Cracks drawn on pieces: segments (x0, y0, x1, y1) relative to the piece; `ChaosBody.crack` indexes this list.
    public private(set) var crackSets: [[SIMD4<Float>]] = []
    private var crackSegmentTotal = 0
    private static let maxCrackSegments = 30_000

    /// The nuclear blast happens once per session; the renderer sets this when it restarts the world.
    public var nukeSpent = false
    private var nukeStart: Float?
    public private(set) var nukeCenter = SIMD2<Float>(0, 0)
    private var nukeFlash: Float = 0
    private var nukeShake: Float = 0
    /// How many pieces the shock wave may still hit, and how many window pieces it may still break.
    private var nukeBudget = 0
    private var nukeBreaks = 0
    /// How far the shock wave goes: a patch of the screen, not all of it.
    public var nukeReach: Float { min(size.x, size.y) * 0.4 }
    private var eventFlash: Float = 0
    private var eventShake: Float = 0
    /// Whiteout of the screen (0...1), from the nuke and from the big explosions.
    public var flash: Float { max(eventFlash, nukeFlash) }
    /// How far the whole picture is shaken, in points.
    public var shake: Float { eventShake + nukeShake }

    // Spatial grid of the original shards: tells whether a piece is hidden behind another window.
    private let coverCell: Float = 48
    private var coverCols = 0, coverRows = 0
    private var coverHead: [Int32] = []
    private var coverNodes: [(shard: Int32, next: Int32)] = []

    private var gridHead: [Int32] = []
    private var gridNext: [Int32] = []

    public init(seeds: [ChaosSeed], size: SIMD2<Float>, settings: ChaosSettings = ChaosSettings()) {
        self.size = size
        self.settings = settings
        rng = SplitMix64(seed: settings.seed != 0 ? settings.seed : UInt64.random(in: 1...UInt64.max))
        for s in seeds {
            let body: ChaosBody
            switch s.kind {
            case .glyph:
                body = Self.makeBody(s, radius: max(2.5, 0.42 * max(s.bodySize.x, s.bodySize.y)), restitution: 0.36, friction: 0.6, massDivisor: 80)
            case .button:
                body = Self.makeBody(s, radius: 0.5 * max(s.bodySize.x, s.bodySize.y), restitution: 0.55, friction: 0.6, massDivisor: 80)
            case .icon:
                body = Self.makeBody(s, radius: 0.46 * (s.bodySize.x + s.bodySize.y) * 0.5, restitution: 0.5, friction: 0.6, massDivisor: 80)
            case .shard:
                let poly = s.polygon ?? ChaosPolygon(verts: [], uvOffset: .zero, uvScale: .zero)
                var shard = Self.makeBody(s, radius: max(3, 0.9 * (poly.area / .pi).squareRoot()), restitution: 0.22, friction: 0.7,
                                          mass: max(1, poly.area / 160))
                polygons.append(poly)
                shard.polygon = Int32(polygons.count - 1)
                body = shard
            }
            bodies.append(body)
        }
        originalCount = bodies.count
        originalPolygonCount = polygons.count
        maxBodies = originalCount + 12_000
        nextEvent = 0.6
        buildCoverGrid()
    }

    private static func makeBody(_ s: ChaosSeed, radius: Float, restitution: Float, friction: Float, massDivisor: Float = 80, mass: Float? = nil) -> ChaosBody {
        let mass = mass ?? max(1, s.bodySize.x * s.bodySize.y / massDivisor)
        return ChaosBody(kind: s.kind, sprite: s.sprite, group: s.group, pos: s.center, size: s.size, radius: radius, invMass: 1 / mass,
                         restitution: restitution, friction: friction, home: s.center, isDock: s.isDock)
    }

    // MARK: - Random helpers

    func random(_ range: ClosedRange<Float>) -> Float { Float.random(in: range, using: &rng) }
    func chance(_ p: Float) -> Bool { random(0...1) < p }
    private var intensity: Float { Float(settings.intensity) }

    // MARK: - Cover grid

    private func buildCoverGrid() {
        coverCols = Int(size.x / coverCell) + 2
        coverRows = Int(size.y / coverCell) + 2
        coverHead = [Int32](repeating: -1, count: coverCols * coverRows)
        coverNodes.removeAll()
        for i in 0..<originalCount where bodies[i].kind == .shard {
            let b = bodies[i]
            let poly = polygons[Int(b.polygon)]
            let lo = b.home + poly.boundsMin, hi = b.home + poly.boundsMax
            let x0 = max(0, Int(lo.x / coverCell)), x1 = min(coverCols - 1, Int(hi.x / coverCell))
            let y0 = max(0, Int(lo.y / coverCell)), y1 = min(coverRows - 1, Int(hi.y / coverCell))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    coverNodes.append((Int32(i), coverHead[y * coverCols + x]))
                    coverHead[y * coverCols + x] = Int32(coverNodes.count - 1)
                }
            }
        }
    }

    private func inPlace(_ state: ChaosBody.State) -> Bool { state == .attached || state == .pending || state == .fuse }

    /// Whether a piece still part of the desktop is hidden behind a window that is in front of it.
    public func isOccluded(_ i: Int) -> Bool {
        let b = bodies[i]
        let cx = min(coverCols - 1, max(0, Int(b.home.x / coverCell))), cy = min(coverRows - 1, max(0, Int(b.home.y / coverCell)))
        var n = coverHead[cy * coverCols + cx]
        while n >= 0 {
            let node = coverNodes[Int(n)]
            let s = bodies[Int(node.shard)]
            if s.group > b.group, inPlace(s.state), polygons[Int(s.polygon)].contains(b.home - s.home) { return true }
            n = node.next
        }
        return false
    }

    // MARK: - Events

    /// Picks an event by weight and runs it; tries the others when it does not apply (nothing left of that kind).
    @discardableResult
    public func triggerEvent() -> ChaosEvent? {
        var pool = ChaosEvent.allCases
        while !pool.isEmpty {
            let total = pool.reduce(0) { $0 + weight(of: $1) }
            var pick = random(0...total)
            var index = pool.count - 1
            for (k, e) in pool.enumerated() {
                pick -= weight(of: e)
                if pick <= 0 { index = k; break }
            }
            let event = pool.remove(at: index)
            if weight(of: event) > 0, run(event) { return event }
        }
        return nil
    }

    /// The nuke is rare: not before 25 s, then one event in about fifteen, and certain after two minutes. Only once.
    private func weight(of event: ChaosEvent) -> Float {
        guard event == .nuke else { return event.weight }
        guard !nukeSpent, time > 25 else { return 0 }
        return time > 120 ? 1000 : 0.8
    }

    /// Runs one kind of event; false when there is nothing left it could act on.
    @discardableResult
    public func run(_ event: ChaosEvent) -> Bool {
        let done: Bool
        switch event {
        case .bomb: done = bomb()
        case .letterShed: done = letterShed()
        case .buttonBlast: done = buttonBlast()
        case .shardCrumble: done = shardCrumble()
        case .quake: done = quake()
        case .nuke: done = startNuke()
        }
        if done { eventCount += 1; lastEvent = event }
        return done
    }

    /// A random piece that is still in place and visible, of one of the given kinds.
    private func pickExposed(_ kinds: [ChaosPieceKind], dockOnly: Bool = false) -> Int? {
        var candidates: [Int] = []
        for i in 0..<originalCount where bodies[i].state == .attached && kinds.contains(bodies[i].kind) && (!dockOnly || bodies[i].isDock) {
            candidates.append(i)
        }
        guard !candidates.isEmpty else { return nil }
        for _ in 0..<16 {
            let i = candidates[Int.random(in: 0..<candidates.count, using: &rng)]
            if !isOccluded(i) { return i }
        }
        return nil
    }

    private func bomb() -> Bool {
        guard let anchor = pickExposed([.shard, .glyph, .icon, .shard]) else { return false }
        let p = bodies[anchor].pos + SIMD2(random(-20...20), random(-20...20))
        let radius = random(100...160) * intensity
        explosionPuffs(at: p, strength: 0.9 + 0.35 * intensity)
        addCracks(at: p, radius: radius, rays: 6 + Int(random(0...3)), rings: 2)
        blast(at: p, radius: radius, strength: intensity, chain: true)
        eventShake = max(eventShake, 3 * intensity)
        eventFlash = max(eventFlash, 0.06)
        return true
    }

    private func letterShed() -> Bool {
        guard let anchor = pickExposed([.glyph]) else { return false }
        let c = bodies[anchor].pos
        let row = chance(0.5)
        let radius = random(60...120) * (0.8 + 0.3 * intensity)
        var released = 0
        for i in 0..<originalCount where bodies[i].kind == .glyph && bodies[i].state == .attached {
            let d = bodies[i].pos - c
            let inside = row ? (abs(d.y) < 11 && abs(d.x) < 150) : simd_length(d) < radius
            guard inside, !isOccluded(i) else { continue }
            let delay = row ? abs(d.x) / 380 + random(0...0.12) : simd_length(d) / radius * 0.8 + random(0...0.25)
            schedule(i, delay: delay, velocity: SIMD2(random(-40...40), random(-20...50)), spin: random(-4...4))
            released += 1
            if released > 40 { break }
        }
        return released > 0
    }

    private func buttonBlast() -> Bool {
        // Now and then it is an icon of the Dock, which blows up much harder.
        if chance(0.3), let dock = pickExposed([.icon], dockOnly: true) {
            ignite(dock, delay: random(0.9...1.4))
            return true
        }
        guard let i = pickExposed([.button, .button, .icon]) else { return false }
        ignite(i, delay: random(0.7...1.3))
        return true
    }

    /// Lights the fuse of a piece right now (tests and scripted use).
    public func detonate(_ i: Int) {
        guard bodies.indices.contains(i) else { return }
        ignite(i, delay: 0.05)
    }

    private func shardCrumble() -> Bool {
        guard let anchor = pickExposed([.shard]) else { return false }
        let c = bodies[anchor].pos
        let reach = random(60...120) * (0.8 + 0.3 * intensity)
        // The crack runs on across the neighbours that hold.
        addCracks(at: c, radius: reach * 1.6, rays: 4, rings: 0)
        var released = 0
        for i in 0..<originalCount where bodies[i].kind == .shard && bodies[i].state == .attached {
            let d = bodies[i].pos - c
            let dist = simd_length(d)
            guard dist < reach, i == anchor || chance(0.7), !isOccluded(i) else { continue }
            // The crack spreads: farther pieces let go a little later.
            schedule(i, delay: dist / 420 + random(0...0.15), velocity: SIMD2(d.x / max(dist, 1) * random(10...60), random(-30...30)), spin: random(-2.5...2.5))
            released += 1
        }
        return released > 0
    }

    private func quake() -> Bool {
        guard time - lastQuake > 4 else { return false }
        var hopped = 0
        // Only pieces that rest on something jump: the ones in the air are left alone, so repeated quakes add no energy.
        for i in 0..<bodies.count where bodies[i].state == .loose && (bodies[i].asleep || bodies[i].grounded) {
            bodies[i].vel = SIMD2(random(-80...80), -random(180...420) * intensity)
            bodies[i].angVel += random(-4...4)
            bodies[i].asleep = false
            bodies[i].sleepTimer = 0
            hopped += 1
        }
        var loosened = 0
        for _ in 0..<(4 + Int(3 * intensity)) {
            guard let i = pickExposed([.shard, .glyph, .glyph, .icon]) else { break }
            schedule(i, delay: random(0...0.5), velocity: SIMD2(random(-60...60), random(-80...0)), spin: random(-3...3))
            loosened += 1
        }
        if hopped + loosened > 0 {
            lastQuake = time
            for _ in 0..<14 { emit(.dust, at: SIMD2(random(0...size.x), size.y - random(0...20)), velocity: SIMD2(random(-60...60), random(-60...(-10))), size: random(18...40), growth: random(20...50), life: random(0.8...1.6)) }
        }
        return hopped + loosened > 0
    }

    // MARK: - Pieces coming loose

    /// The piece lets go of the desktop after `delay` seconds.
    private func schedule(_ i: Int, delay: Float, velocity: SIMD2<Float>, spin: Float) {
        guard bodies[i].state == .attached else { return }
        bodies[i].state = .pending
        bodies[i].timer = delay
        bodies[i].vel = velocity
        bodies[i].angVel = spin
        carry(from: i, delay: delay, velocity: velocity, spin: spin)
    }

    /// Letters and icons that sit on a piece of the window come with it (charred when the piece was hit by a blast).
    private func carry(from shard: Int, delay: Float, velocity: SIMD2<Float>, spin: Float, scorched: Float = 0) {
        guard bodies[shard].kind == .shard else { return }
        let s = bodies[shard]
        for j in 0..<originalCount where bodies[j].state == .attached && bodies[j].kind != .shard && bodies[j].group == s.group {
            guard polygons[Int(s.polygon)].contains(bodies[j].home - s.home) else { continue }
            bodies[j].state = .pending
            bodies[j].timer = delay + random(0...0.05)
            bodies[j].vel = velocity + SIMD2(random(-30...30), random(-30...10))
            bodies[j].angVel = spin + random(-1.5...1.5)
            if scorched > 0 { scorch(j, scorched) }
        }
    }

    private func release(_ i: Int) {
        bodies[i].state = .loose
        bodies[i].age = 0
        bodies[i].asleep = false
        bodies[i].sleepTimer = 0
    }

    private func launch(_ i: Int, velocity: SIMD2<Float>, spin: Float) {
        if inPlace(bodies[i].state) {
            bodies[i].vel = velocity
            bodies[i].angVel = spin
            release(i)
            carry(from: i, delay: 0, velocity: velocity, spin: spin, scorched: 0.6)
        } else {
            bodies[i].vel += velocity
            bodies[i].angVel += spin
            bodies[i].asleep = false
            bodies[i].sleepTimer = 0
        }
    }

    /// Starts a button or icon blinking: it explodes when the fuse is out.
    private func ignite(_ i: Int, delay: Float) {
        guard bodies[i].state == .attached || bodies[i].state == .pending else { return }
        bodies[i].state = .fuse
        bodies[i].timer = delay
    }

    // MARK: - Blasts

    private func blast(at p: SIMD2<Float>, radius R: Float, strength S: Float, chain: Bool) {
        largestBlastRadius = max(largestBlastRadius, R)
        let count = bodies.count
        for i in 0..<count {
            let state = bodies[i].state
            guard state != .gone else { continue }
            let d = bodies[i].pos - p
            let dist = simd_length(d)
            guard dist < R + bodies[i].effectiveRadius else { continue }
            let falloff = max(0, 1 - dist / R)
            let dir = dist > 0.5 ? d / dist : SIMD2<Float>(0, -1)
            let heavy = 1 / (1 + 0.12 * (1 / bodies[i].invMass).squareRoot())
            let speed = S * (200 + 560 * falloff) * heavy * random(0.8...1.2)
            let velocity = dir * speed + SIMD2(0, -220 * falloff * S)
            let spin = random(-9...9) * (0.3 + falloff)

            switch state {
            case .attached, .pending:
                guard !isOccluded(i) else { continue }
                if chain, bodies[i].kind == .button, dist > 4 {
                    ignite(i, delay: 0.18 + dist / R * 0.55 + random(0...0.25))
                    continue
                }
                guard dist < R * (0.72 + 0.28 * random(0...1)) else { continue }
                if bodies[i].kind == .shard, falloff > 0.4, bodies.count < maxBodies - 16 {
                    fracture(i, from: p, strength: S, falloff: falloff, burn: 0.45 + 0.55 * falloff)
                } else {
                    launch(i, velocity: velocity, spin: spin)
                    scorch(i, 0.3 + 0.7 * falloff)
                }
            case .loose:
                launch(i, velocity: velocity * 0.7, spin: spin)
                scorch(i, 0.3 + 0.5 * falloff)
            case .fuse:
                if bodies[i].timer > 0.25 { bodies[i].timer = 0.12 + random(0...0.12) }
            case .gone:
                break
            }
        }
    }

    /// Chars the edges of a piece and makes them glow; letters and icons get a dark, singed tint.
    private func scorch(_ i: Int, _ amount: Float) {
        bodies[i].burn = max(bodies[i].burn, min(1, amount))
        bodies[i].heat = max(bodies[i].heat, min(1, amount + 0.3))
        if bodies[i].kind != .shard, bodies[i].state != .fuse {
            bodies[i].tint = SIMD4(0.06, 0.035, 0.02, min(0.75, 0.25 + amount * 0.5))
        }
    }

    /// Seeds of the cracks of a shard hit at `p`, like in glass: rings of points around the impact that grow farther apart
    /// (small, sharp pieces near the hit, bigger ones away from it) and are shifted a little so no two are alike.
    private func crackSites(around p: SIMD2<Float>, in lo: SIMD2<Float>, _ hi: SIMD2<Float>, falloff: Float) -> [SIMD2<Float>] {
        let margin: Float = 28
        let farthest = max(simd_length(SIMD2(lo.x, lo.y) - p), simd_length(SIMD2(hi.x, lo.y) - p),
                           simd_length(SIMD2(lo.x, hi.y) - p), simd_length(SIMD2(hi.x, hi.y) - p))
        var sites: [SIMD2<Float>] = []
        var r = random(10...22) * (1.3 - 0.5 * falloff)
        while r < farthest + margin {
            let spacing = (24 + 0.32 * r) * (1.35 - 0.45 * falloff)
            let n = max(5, Int(2 * Float.pi * r / spacing))
            let a0 = random(0...(2 * .pi))
            for k in 0..<n {
                let a = a0 + (Float(k) + random(-0.32...0.32)) * 2 * .pi / Float(n)
                let s = p + SIMD2(cos(a), sin(a)) * r * random(0.88...1.12)
                if s.x > lo.x - margin, s.x < hi.x + margin, s.y > lo.y - margin, s.y < hi.y + margin { sites.append(s) }
            }
            r *= random(1.5...1.8)
        }
        if sites.count > 14 { sites = Array(sites.shuffled(using: &rng).prefix(14)) }
        return sites
    }

    /// A shard close to a blast breaks into jagged convex fragments along cracks that spread from the impact.
    private func fracture(_ i: Int, from p: SIMD2<Float>, strength S: Float, falloff: Float, burn: Float) {
        let parent = bodies[i]
        let poly = polygons[Int(parent.polygon)]
        let outline = poly.verts.map { parent.home + $0 }
        let lo = parent.home + poly.boundsMin, hi = parent.home + poly.boundsMax
        var sites = crackSites(around: p, in: lo, hi, falloff: falloff)
        // At least three sites inside the piece, or it would not break.
        var inside = sites.filter { ChaosGeometry.contains(outline, $0) }.count
        var attempts = 0
        while inside < 3, attempts < 40 {
            attempts += 1
            let s = SIMD2(random(lo.x...hi.x), random(lo.y...hi.y))
            if ChaosGeometry.contains(outline, s) { sites.append(s); inside += 1 }
        }

        let dirToParent = parent.pos - p
        let base = simd_length(dirToParent) > 0.5 ? dirToParent / simd_length(dirToParent) : SIMD2<Float>(0, -1)
        carry(from: i, delay: 0, velocity: base * 400 * S, spin: random(-4...4), scorched: 0.6)
        bodies[i].state = .gone
        wakePoints.append(parent.pos)

        for index in sites.indices {
            let cell = ChaosGeometry.cell(of: index, in: sites, bounds: outline)
            guard cell.count >= 3 else { continue }
            let area = ChaosGeometry.area(cell)
            guard area > 6 else { continue }
            let g = ChaosGeometry.centroid(cell)
            var child = parent
            let local = g - parent.home
            polygons.append(ChaosPolygon(verts: cell.map { $0 - g }, uvOffset: poly.uvOffset + local * poly.uvScale, uvScale: poly.uvScale))
            child.polygon = Int32(polygons.count - 1)
            child.pos = g
            child.home = g
            let bounds = (cell.map { $0 - g })
            child.size = bounds.dropFirst().reduce(bounds[0]) { simd_max($0, $1) } - bounds.dropFirst().reduce(bounds[0]) { simd_min($0, $1) }
            child.radius = max(2.5, 0.9 * (area / .pi).squareRoot())
            child.invMass = 1 / max(1, area / 160)
            let d = g - p
            let dist = max(simd_length(d), 1)
            let speed = S * random(240...640) / (1 + 0.005 * dist)
            child.vel = d / dist * speed + SIMD2(0, -random(50...170))
            child.angVel = random(-8...8)
            child.angle = 0
            child.state = .loose
            child.age = 0
            child.asleep = false
            child.sleepTimer = 0
            child.isChild = true
            child.crack = -1
            child.burn = burn
            child.heat = 1
            bodies.append(child)
        }
        // The break raises a little dust along the cracks.
        for _ in 0..<min(10, sites.count) {
            emit(.dust, at: SIMD2(random(lo.x...hi.x), random(lo.y...hi.y)), velocity: SIMD2(random(-40...40), random(-50...10)),
                 size: random(8...16), growth: random(20...40), life: random(0.6...1.2))
        }
    }

    private func explode(_ i: Int) {
        let p = bodies[i].pos
        let wasIcon = bodies[i].kind == .icon
        let dock = bodies[i].isDock
        bodies[i].state = .gone
        wakePoints.append(p)
        if dock {
            // An icon of the Dock goes off far harder than anything else on the screen.
            let radius = random(250...320) * intensity
            explosionPuffs(at: p, strength: 2.2 + 0.5 * intensity, big: true)
            eventFlash = max(eventFlash, 0.45)
            eventShake = max(eventShake, 14 * intensity)
            addCracks(at: p, radius: radius * 0.9, rays: 10, rings: 3)
            blast(at: p, radius: radius, strength: 2 * intensity, chain: true)
        } else {
            explosionPuffs(at: p, strength: (wasIcon ? 0.85 : 0.7) + 0.25 * intensity)
            addCracks(at: p, radius: random(70...100) * intensity, rays: 4, rings: 1)
            blast(at: p, radius: random(70...100) * intensity, strength: 0.75 * intensity, chain: true)
            eventShake = max(eventShake, 1.5 * intensity)
        }
    }

    // MARK: - Cracks

    /// Jagged lines from the impact (with now and then a side branch) and a few arcs around it, like the cracks of glass.
    private func crackPolylines(at p: SIMD2<Float>, radius R: Float, rays: Int, rings: Int) -> [[SIMD2<Float>]] {
        var lines: [[SIMD2<Float>]] = []
        for _ in 0..<rays {
            var a = random(0...(2 * .pi))
            let length = R * random(0.8...1.35)
            var r = random(0...10)
            var points = [p + SIMD2(cos(a), sin(a)) * r]
            while r < length {
                r += random(9...17)
                a += random(-0.13...0.13)
                let d = SIMD2(cos(a), sin(a))
                let point = p + d * r + SIMD2(-d.y, d.x) * random(-2.5...2.5)
                points.append(point)
                if chance(0.12) {
                    var b = a + random(-0.9...0.9)
                    var branch = [point]
                    for _ in 0..<Int(random(2...4)) {
                        b += random(-0.25...0.25)
                        branch.append(branch[branch.count - 1] + SIMD2(cos(b), sin(b)) * random(10...18))
                    }
                    lines.append(branch)
                }
            }
            lines.append(points)
        }
        for _ in 0..<rings {
            let r = R * random(0.25...0.85), sweep = random(0.8...2.6), start = random(0...(2 * .pi))
            let steps = max(3, Int(sweep * r / 13))
            lines.append((0...steps).map { k in
                let a = start + sweep * Float(k) / Float(steps), rr = r + random(-2.5...2.5)
                return p + SIMD2(cos(a), sin(a)) * rr
            })
        }
        return lines
    }

    /// Draws cracks on the pieces of window near `p` that stay in place; a piece that comes loose later takes them along.
    private func addCracks(at p: SIMD2<Float>, radius R: Float, rays: Int, rings: Int) {
        guard crackSegmentTotal < Self.maxCrackSegments else { return }
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        for line in crackPolylines(at: p, radius: R, rays: rays, rings: rings) {
            for k in 0..<(line.count - 1) { segments.append((line[k], line[k + 1])) }
        }
        let reach = R * 1.5
        for i in 0..<originalCount where bodies[i].kind == .shard && inPlace(bodies[i].state) {
            let b = bodies[i]
            guard simd_length(b.home - p) < reach + b.radius, !isOccluded(i) else { continue }
            let outline = polygons[Int(b.polygon)].verts
            var local: [SIMD4<Float>] = []
            for (a, c) in segments {
                if let (s0, s1) = ChaosGeometry.clipSegment(a - b.home, c - b.home, to: outline), simd_distance(s0, s1) > 1.5 {
                    local.append(SIMD4(s0.x, s0.y, s1.x, s1.y))
                }
            }
            guard !local.isEmpty else { continue }
            if bodies[i].crack < 0 {
                crackSets.append([])
                bodies[i].crack = Int32(crackSets.count - 1)
            }
            let k = Int(bodies[i].crack)
            let room = max(0, 80 - crackSets[k].count)
            crackSets[k].append(contentsOf: local.prefix(room))
            crackSegmentTotal += min(room, local.count)
        }
    }

    // MARK: - Nuclear blast

    /// A ground burst with a flash, a shock wave that tears everything apart, a fireball and a mushroom cloud.
    private func startNuke() -> Bool {
        guard !nukeSpent, nukeStart == nil else { return false }
        guard (0..<originalCount).contains(where: { inPlace(bodies[$0].state) }) else { return false }
        nukeSpent = true
        nukeStart = time
        nukeBudget = 450
        nukeBreaks = 24
        nukeCenter = SIMD2(size.x * random(0.3...0.7), size.y)
        let c = nukeCenter
        for _ in 0..<36 {
            let a = random((-Float.pi * 0.98)...(-Float.pi * 0.02)), s = random(60...320)
            emit(.flame, at: c + SIMD2(random(-40...40), -random(10...50)), velocity: SIMD2(cos(a), sin(a)) * s, size: random(40...80),
                 growth: random(25...60), life: random(0.9...1.8))
        }
        for _ in 0..<90 {
            let a = random((-Float.pi * 0.98)...(-Float.pi * 0.02)), s = random(200...800)
            emit(.spark, at: c + SIMD2(random(-30...30), -random(0...30)), velocity: SIMD2(cos(a), sin(a)) * s, size: random(1.5...4), growth: 0, life: random(1.2...2.8))
        }
        return true
    }

    private func updateNuke(_ dt: Float) {
        guard let start = nukeStart else { return }
        let t = time - start
        nukeFlash = 0.55 * (t < 0.08 ? t / 0.08 : exp(-(t - 0.08) * 3.2))
        nukeShake = 9 * exp(-t * 1.6)
        shockwave(radius: min(800 * t, nukeReach))
        emitMushroom(t: t, dt: dt)
        if t > 6 {
            nukeStart = nil
            nukeFlash = 0
            nukeShake = 0
        }
    }

    /// Everything the front of the wave reaches is broken, thrown and charred.
    private func shockwave(radius: Float) {
        let c = nukeCenter
        let count = bodies.count
        for i in 0..<count {
            let state = bodies[i].state
            guard state != .gone, !bodies[i].shocked else { continue }
            let d = bodies[i].pos - c
            let dist = simd_length(d)
            guard dist <= radius else { continue }
            if inPlace(state), isOccluded(i) { continue }
            bodies[i].shocked = true
            // Farther pieces are less and less likely to be touched, and the wave runs out of strength after a while.
            if state != .fuse, nukeBudget <= 0 || random(0...1) > 1 - 0.65 * dist / nukeReach { continue }
            nukeBudget -= 1
            let f = 1 / (1 + (dist / 200) * (dist / 200))
            var dir = dist > 0.5 ? d / dist : SIMD2<Float>(0, -1)
            dir.y -= 0.45
            dir /= simd_length(dir)
            let heavy = 1 / (1 + 0.08 * (1 / bodies[i].invMass).squareRoot())
            let velocity = dir * (180 + 700 * f) * heavy * random(0.85...1.15)
            let spin = random(-9...9) * (0.3 + f)
            switch state {
            case .fuse:
                bodies[i].timer = min(bodies[i].timer, 0.1 + dist / 1500)
            case .attached, .pending:
                if bodies[i].kind == .shard, nukeBreaks > 0, dist < nukeReach * 0.6, bodies.count < maxBodies - 16 {
                    nukeBreaks -= 1
                    fracture(i, from: c, strength: 1.1, falloff: 0.1 + 0.4 * f, burn: 1)
                } else {
                    launch(i, velocity: velocity, spin: spin)
                    scorch(i, 1)
                }
            case .loose:
                launch(i, velocity: velocity * 0.6, spin: spin)
                scorch(i, 0.9)
            case .gone:
                break
            }
        }
    }

    /// Number of things to emit in `dt` at `rate` per second, with the fraction decided by chance.
    private func emitCount(_ rate: Float, _ dt: Float) -> Int {
        let x = rate * dt
        return Int(x) + (random(0...1) < x - Float(Int(x)) ? 1 : 0)
    }

    private func emitMushroom(t: Float, dt: Float) {
        let c = nukeCenter
        let floorY = size.y
        let height = size.y * 0.45 * (1 - exp(-t * 0.8))
        let headY = floorY - height

        if t < 4 {   // the stem
            for _ in 0..<emitCount(40, dt) {
                let s = random(0...1)
                let y = floorY - 15 - s * max(height - 15, 0)
                let w = 12 + 30 * (1 - s) * (1 - s)
                let at = SIMD2(c.x + random(-w...w), y)
                if chance(0.6) {
                    emit(.smoke, at: at, velocity: SIMD2(random(-10...10), -random(25...80)), size: random(20...38), growth: random(10...20), life: random(2.2...3.8))
                } else {
                    emit(.flame, at: at, velocity: SIMD2(random(-12...12), -random(50...120)), size: random(14...26), growth: random(5...18), life: random(0.6...1.2))
                }
            }
        }
        if t > 0.6, t < 4.5 {   // the cap rolls outwards and down at its edges
            let capRadius = 30 + 80 * min(1, t / 3)
            for _ in 0..<emitCount(55, dt) {
                let th = random(0...(2 * .pi))
                let rx = capRadius * random(0.75...1.25) * 1.15, ry = capRadius * 0.5 * random(0.7...1.2)
                let at = SIMD2(c.x + cos(th) * rx, headY + sin(th) * ry - ry * 0.3)
                let v = SIMD2(cos(th) * 40, sin(th) * 25 - 18)
                if sin(th) > 0.2, chance(0.5) {
                    emit(.flame, at: at, velocity: v, size: random(20...36), growth: random(4...12), life: random(0.7...1.3))
                } else {
                    emit(.smoke, at: at, velocity: v, size: random(30...52), growth: random(10...20), life: random(2.5...4.2))
                }
            }
        }
        let ring = 800 * t   // a little dust runs along the ground ahead of the wave
        if ring < nukeReach {
            for side in [Float(-1), Float(1)] {
                for _ in 0..<emitCount(22, dt) {
                    let x = c.x + side * ring * random(0.85...1.0)
                    guard x > 0, x < size.x else { continue }
                    emit(.dust, at: SIMD2(x, floorY - random(4...20)), velocity: SIMD2(side * random(100...260), -random(10...40)), size: random(20...40),
                         growth: random(20...40), life: random(1.0...2.0))
                }
            }
        }
        if t < 1.5 {   // embers thrown up by the fireball
            for _ in 0..<emitCount(40, dt) {
                let a = random((-Float.pi * 0.9)...(-Float.pi * 0.1)), s = random(150...600)
                emit(.spark, at: SIMD2(c.x + random(-25...25), floorY - random(0...40)), velocity: SIMD2(cos(a), sin(a)) * s, size: random(1.5...3.5), growth: 0, life: random(1.2...2.6))
            }
        }
        if t < 3 {   // fine dust in the air around the burst
            for _ in 0..<emitCount(60, dt) {
                emit(.mote, at: SIMD2(c.x + random(-nukeReach...nukeReach), random((size.y * 0.4)...size.y)), velocity: SIMD2(random(-25...25), random(-35...10)), size: random(1...3), growth: 0, life: random(1.5...3))
            }
        }
    }

    // MARK: - Puffs

    func emit(_ kind: ChaosPuff.Kind, at p: SIMD2<Float>, velocity v: SIMD2<Float>, size: Float, growth: Float, life: Float) {
        guard puffs.count < Self.maxPuffs else { return }
        puffs.append(ChaosPuff(pos: p, vel: v, size: size, growth: growth, age: 0, life: life, kind: kind))
    }

    private func explosionPuffs(at p: SIMD2<Float>, strength: Float, big: Bool = false) {
        for _ in 0..<Int(30 * strength) {
            let a = random(0...(2 * .pi)), s = random(30...260) * strength
            emit(.flame, at: p, velocity: SIMD2(cos(a), sin(a)) * s, size: random(14...34) * strength, growth: random(-10...20), life: random(0.35...0.9))
        }
        // Sparks, some fast and thin, some slow and fat that fall back as embers.
        for _ in 0..<Int(48 * strength) {
            let a = random(0...(2 * .pi)), s = random(100...720) * strength
            emit(.spark, at: p, velocity: SIMD2(cos(a), sin(a)) * s, size: random(1.5...4.5), growth: 0, life: random(0.7...2.2))
        }
        for _ in 0..<Int(30 * strength) {
            let a = random(0...(2 * .pi)), s = random(20...150) * strength
            emit(.smoke, at: p + SIMD2(cos(a), sin(a)) * random(0...20), velocity: SIMD2(cos(a), sin(a)) * s - SIMD2(0, 30),
                 size: random(20...55) * strength, growth: random(25...60), life: random(1.5...3.5))
        }
        // Fine dust that hangs in the air.
        for _ in 0..<Int(70 * strength) {
            let a = random(0...(2 * .pi)), s = random(15...170) * strength
            emit(.mote, at: p + SIMD2(cos(a), sin(a)) * random(0...40), velocity: SIMD2(cos(a), sin(a)) * s, size: random(1.2...3.5), growth: 0, life: random(1.6...4))
        }
        if big {
            // A ring of dust and smoke runs out along the screen.
            for k in 0..<56 {
                let a = Float(k) / 56 * 2 * .pi + random(-0.05...0.05)
                emit(.dust, at: p, velocity: SIMD2(cos(a), sin(a)) * random(380...620), size: random(18...30), growth: random(50...90), life: random(0.7...1.2))
            }
        }
    }

    private func updatePuffs(_ dt: Float) {
        var i = 0
        while i < puffs.count {
            puffs[i].age += dt
            if puffs[i].age >= puffs[i].life { puffs.swapAt(i, puffs.count - 1); puffs.removeLast(); continue }
            switch puffs[i].kind {
            case .smoke: puffs[i].vel = puffs[i].vel * (1 - 1.2 * dt) - SIMD2(0, 18 * dt)
            case .flame: puffs[i].vel = puffs[i].vel * (1 - 2.5 * dt) - SIMD2(0, 90 * dt)
            case .spark: puffs[i].vel = puffs[i].vel * (1 - 0.8 * dt) + SIMD2(0, 500 * dt)
            case .dust: puffs[i].vel *= 1 - 3 * dt
            case .mote: puffs[i].vel = puffs[i].vel * (1 - 1.3 * dt) - SIMD2(0, 9 * dt)
            }
            puffs[i].pos += puffs[i].vel * dt
            puffs[i].size = max(0.5, puffs[i].size + puffs[i].growth * dt)
            i += 1
        }
    }

    // MARK: - Stepping

    /// Advances the world by `dt` real seconds.
    public func step(dt rawDt: Float) {
        accumulator += min(rawDt, 0.1) * Float(settings.speed)
        var steps = 0
        let h: Float = 1 / 120
        while accumulator >= h, steps < 3 {
            substep(h)
            accumulator -= h
            steps += 1
        }
        if steps == 3 { accumulator = 0 }
    }

    /// True once most of the desktop is gone and what fell has settled or faded: time to restore it.
    public var isExhausted: Bool { time > 4 && intactFraction < 0.07 && looseCount < 40 && nukeStart == nil }

    private func substep(_ dt: Float) {
        time += dt
        if automaticEvents, time >= nextEvent {
            triggerEvent()
            nextEvent = time + Float(settings.eventInterval / 1000 * settings.speed) * random(0.7...1.3)
        }
        updateScripted(dt)
        updateNuke(dt)
        eventFlash = max(0, eventFlash - dt * 1.6)
        eventShake = max(0, eventShake - dt * 16)
        let ageRate = 1 + Float(max(0, looseCount - Self.comfortableLoose)) / 400
        let g = SIMD2<Float>(0, gravity)
        var loose = 0
        for i in bodies.indices where bodies[i].state == .loose {
            loose += 1
            bodies[i].age += dt * ageRate / Float(settings.speed)
            let remaining = Float(settings.lifetime) - bodies[i].age
            if remaining <= 0 {
                bodies[i].state = .gone
                wakePoints.append(bodies[i].pos)
                continue
            }
            bodies[i].alpha = min(1, remaining / 1.2)
            if bodies[i].heat > 0 { bodies[i].heat = max(0, bodies[i].heat - dt * 0.3) }
            guard !bodies[i].asleep else { continue }
            // Pieces lying on something lose their jitter quickly: a pile settles instead of shivering.
            if bodies[i].grounded {
                let resting = simd_length_squared(bodies[i].vel) < 22_500
                bodies[i].vel *= 1 / (1 + (resting ? 25 : 5) * dt)
                bodies[i].angVel *= 1 / (1 + (resting ? 12 : 3) * dt)
            }
            bodies[i].grounded = false
            bodies[i].vel += g * dt
            bodies[i].vel *= 1 / (1 + drag * dt)
            bodies[i].angVel *= 1 / (1 + 0.15 * dt)
            bodies[i].pos += bodies[i].vel * dt
            bodies[i].angle += bodies[i].angVel * dt
            collideWalls(i)
        }
        looseCount = loose
        collideBodies()
        keepInside()
        updateSleep(dt)
        updatePuffs(dt)
        if time - lastCompaction > 0.5 {
            lastCompaction = time
            updateIntact()
            if time - lastFragmentCleanup > 4 { lastFragmentCleanup = time; compact() }
        }
    }

    /// Fuses and delayed releases.
    private func updateScripted(_ dt: Float) {
        let count = bodies.count
        for i in 0..<count {
            switch bodies[i].state {
            case .pending:
                bodies[i].timer -= dt
                if bodies[i].timer <= 0 { release(i) }
            case .fuse:
                bodies[i].timer -= dt
                let pulse = 0.5 + 0.5 * sin(time * (16 + max(0, 1.2 - bodies[i].timer) * 26))
                bodies[i].tint = SIMD4(1, 0.12, 0.05, 0.6 * pulse)
                bodies[i].scale = 1 + 0.16 * pulse
                bodies[i].flash = 0.25 * pulse
                if bodies[i].timer <= 0 { explode(i) }
            default:
                break
            }
        }
    }

    private func updateIntact() {
        var intact = 0
        for i in 0..<originalCount where inPlace(bodies[i].state) { intact += 1 }
        intactFraction = originalCount > 0 ? Float(intact) / Float(originalCount) : 0
    }

    /// Drops the fragments that are gone (and their outlines); the original pieces keep their place (the cover grid refers to them).
    private func compact() {
        guard bodies.count > originalCount else { return }
        var kept = Array(polygons[0..<originalPolygonCount])
        var write = originalCount
        for read in originalCount..<bodies.count where bodies[read].state != .gone {
            var b = bodies[read]
            if b.polygon >= Int32(originalPolygonCount) {
                kept.append(polygons[Int(b.polygon)])
                b.polygon = Int32(kept.count - 1)
            }
            bodies[write] = b
            write += 1
        }
        polygons = kept
        if write < bodies.count { bodies.removeSubrange(write...) }
    }

    // MARK: - Collisions

    private func resolveStatic(_ i: Int, normal n: SIMD2<Float>, depth: Float) {
        let r = bodies[i].effectiveRadius
        bodies[i].pos += n * depth
        let vn = simd_dot(bodies[i].vel, n)
        if n.y < -0.6 { bodies[i].grounded = true }
        guard vn < 0 else { return }
        if -vn > 260, chance(0.4) {
            emit(.dust, at: bodies[i].pos - n * r, velocity: SIMD2(random(-40...40), -random(10...60)), size: random(5...12),
                 growth: random(15...35), life: random(0.5...1.1))
        }
        let e = -vn > 70 ? bodies[i].restitution : 0
        let invM = bodies[i].invMass, invI = bodies[i].invInertia
        bodies[i].vel += n * (-(1 + e) * vn)
        let jn = -(1 + e) * vn / invM
        let t = SIMD2(-n.y, n.x)
        let slip = simd_dot(bodies[i].vel, t) - bodies[i].angVel * r
        var jt = -slip / (invM + r * r * invI)
        let limit = bodies[i].friction * jn
        jt = max(-limit, min(limit, jt))
        bodies[i].vel += t * (jt * invM)
        bodies[i].angVel += -r * jt * invI
    }

    /// The floor and the two sides of the screen; there is no ceiling, pieces can fly out of the top and come back.
    private func collideWalls(_ i: Int) {
        let r = bodies[i].effectiveRadius, p = bodies[i].pos
        if p.x - r < 0 { resolveStatic(i, normal: SIMD2(1, 0), depth: r - p.x) }
        if p.x + r > size.x { resolveStatic(i, normal: SIMD2(-1, 0), depth: p.x + r - size.x) }
        if p.y + r > size.y { resolveStatic(i, normal: SIMD2(0, -1), depth: p.y + r - size.y) }
    }

    /// Pieces pushed apart in a pile must not sink into the floor or the walls.
    private func keepInside() {
        for i in bodies.indices where bodies[i].state == .loose {
            let r = bodies[i].effectiveRadius
            if bodies[i].pos.y + r > size.y { bodies[i].pos.y = size.y - r; bodies[i].vel.y = min(bodies[i].vel.y, 0) }
            if bodies[i].pos.x - r < 0 { bodies[i].pos.x = r; bodies[i].vel.x = max(bodies[i].vel.x, 0) }
            if bodies[i].pos.x + r > size.x { bodies[i].pos.x = size.x - r; bodies[i].vel.x = min(bodies[i].vel.x, 0) }
        }
    }

    private func collideBodies() {
        var maxR: Float = 8
        var any = false
        for b in bodies where b.state == .loose { maxR = max(maxR, b.radius); any = true }
        guard any else { wakePoints.removeAll(keepingCapacity: true); return }
        let cell = max(24, maxR * 2)
        let cols = Int(size.x / cell) + 2, rows = Int(size.y / cell) + 2
        if gridHead.count != cols * rows { gridHead = [Int32](repeating: -1, count: cols * rows) } else {
            for k in gridHead.indices { gridHead[k] = -1 }
        }
        if gridNext.count != bodies.count { gridNext = [Int32](repeating: -1, count: bodies.count) }
        for i in bodies.indices where bodies[i].state == .loose {
            let p = bodies[i].pos
            let cx = min(cols - 1, max(0, Int(p.x / cell))), cy = min(rows - 1, max(0, Int(p.y / cell)))
            gridNext[i] = gridHead[cy * cols + cx]
            gridHead[cy * cols + cx] = Int32(i)
        }
        // Pieces lying on something that faded away wake up and fall.
        for w in wakePoints {
            let cx = min(cols - 1, max(0, Int(w.x / cell))), cy = min(rows - 1, max(0, Int(w.y / cell)))
            for y in max(0, cy - 1)...min(rows - 1, cy + 1) {
                for x in max(0, cx - 1)...min(cols - 1, cx + 1) {
                    var j = gridHead[y * cols + x]
                    while j >= 0 {
                        if bodies[Int(j)].asleep, simd_distance(bodies[Int(j)].pos, w) < bodies[Int(j)].effectiveRadius + 3 * maxR {
                            bodies[Int(j)].asleep = false
                            bodies[Int(j)].sleepTimer = 0
                        }
                        j = gridNext[Int(j)]
                    }
                }
            }
        }
        wakePoints.removeAll(keepingCapacity: true)

        // Two passes: a pile needs more than one to pass the weight of the upper pieces down to the floor.
        for _ in 0..<2 {
            for i in bodies.indices where bodies[i].state == .loose {
                let p = bodies[i].pos
                let cx = min(cols - 1, max(0, Int(p.x / cell))), cy = min(rows - 1, max(0, Int(p.y / cell)))
                for y in max(0, cy - 1)...min(rows - 1, cy + 1) {
                    for x in max(0, cx - 1)...min(cols - 1, cx + 1) {
                        var j = gridHead[y * cols + x]
                        while j >= 0 {
                            if Int(j) > i { resolvePair(i, Int(j)) }
                            j = gridNext[Int(j)]
                        }
                    }
                }
            }
        }
    }

    private func resolvePair(_ i: Int, _ j: Int) {
        var a = bodies[i], b = bodies[j]
        let delta = b.pos - a.pos
        let ra = a.effectiveRadius, rb = b.effectiveRadius
        let rr = ra + rb
        let d2 = simd_length_squared(delta)
        guard d2 < rr * rr else { return }
        let d = max(d2.squareRoot(), 0.001)
        if a.asleep && b.asleep {
            guard rr - d > 2 else { return }
            a.asleep = false; b.asleep = false
            a.sleepTimer = 0; b.sleepTimer = 0
        }
        let n = d2 > 1e-6 ? delta / d : SIMD2<Float>(0, -1)
        let invSum = a.invMass + b.invMass
        let depth = rr - d
        let correction = max(depth - 0.3, 0) * 0.8 / invSum
        a.pos -= n * (correction * a.invMass)
        b.pos += n * (correction * b.invMass)

        let t = SIMD2(-n.y, n.x)
        let vt = (simd_dot(b.vel, t) - b.angVel * rb) - (simd_dot(a.vel, t) + a.angVel * ra)
        let vn = simd_dot(b.vel - a.vel, n)
        if vn < 0 {
            let e = -vn > 70 ? min(a.restitution, b.restitution) : 0
            let jn = -(1 + e) * vn / invSum
            a.vel -= n * (jn * a.invMass)
            b.vel += n * (jn * b.invMass)
            let kt = invSum + ra * ra * a.invInertia + rb * rb * b.invInertia
            var jt = -vt / kt
            let limit = min(a.friction, b.friction) * jn
            jt = max(-limit, min(limit, jt))
            a.vel -= t * (jt * a.invMass)
            b.vel += t * (jt * b.invMass)
            a.angVel += -ra * jt * a.invInertia
            b.angVel += -rb * jt * b.invInertia
        }
        if n.y > 0.6 { a.grounded = true }   // b lies below a: a rests on it
        if n.y < -0.6 { b.grounded = true }
        let wakeSpeed: Float = 30
        if a.asleep, !b.asleep, simd_length(b.vel - a.vel) > wakeSpeed { a.asleep = false; a.sleepTimer = 0 }
        if b.asleep, !a.asleep, simd_length(b.vel - a.vel) > wakeSpeed { b.asleep = false; b.sleepTimer = 0 }
        bodies[i] = a
        bodies[j] = b
    }

    private func updateSleep(_ dt: Float) {
        for i in bodies.indices where bodies[i].state == .loose && !bodies[i].asleep {
            if simd_length_squared(bodies[i].vel) < 150, abs(bodies[i].angVel) < 1, bodies[i].grounded {
                bodies[i].sleepTimer += dt
                if bodies[i].sleepTimer > 0.6 { bodies[i].asleep = true; bodies[i].vel = .zero; bodies[i].angVel = 0 }
            } else {
                bodies[i].sleepTimer = 0
            }
        }
    }
}
