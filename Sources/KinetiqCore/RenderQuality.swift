// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persist only the user's choice, never the transient Auto estimate.
public enum RenderQuality: String, CaseIterable, Codable, Sendable {
    case auto, low, balanced, high, ultra

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .high: return "High"
        case .ultra: return "Ultra"
        }
    }
}

/// Independent resource limits. Texture scale applies to intermediate fields,
/// not captured text or the native-resolution destination. Mesh limit is per axis.
public struct RenderBudget: Equatable, Sendable {
    public var textureScale: Double
    public var maxParticles: Int
    public var blurPasses: Int
    public var meshLimit: Int
    public var secondaryFPS: Int
    public var allowsExpensive: Bool

    public init(textureScale: Double, maxParticles: Int, blurPasses: Int,
                meshLimit: Int, secondaryFPS: Int, allowsExpensive: Bool) {
        self.textureScale = textureScale
        self.maxParticles = maxParticles
        self.blurPasses = blurPasses
        self.meshLimit = meshLimit
        self.secondaryFPS = secondaryFPS
        self.allowsExpensive = allowsExpensive
    }

    public static func forQuality(_ quality: RenderQuality) -> RenderBudget {
        switch quality {
        case .auto, .high:
            return RenderBudget(textureScale: 1, maxParticles: 1500, blurPasses: 2,
                                meshLimit: 48, secondaryFPS: 90, allowsExpensive: true)
        case .ultra:
            return RenderBudget(textureScale: 1, maxParticles: 1500, blurPasses: 3,
                                meshLimit: 64, secondaryFPS: 120, allowsExpensive: true)
        case .balanced:
            return RenderBudget(textureScale: 0.75, maxParticles: 1000, blurPasses: 1,
                                meshLimit: 32, secondaryFPS: 60, allowsExpensive: true)
        case .low:
            return RenderBudget(textureScale: 0.5, maxParticles: 400, blurPasses: 0,
                                meshLimit: 16, secondaryFPS: 30, allowsExpensive: false)
        }
    }

    fileprivate func capped(by ceiling: RenderBudget) -> RenderBudget {
        RenderBudget(textureScale: min(textureScale, ceiling.textureScale),
                     maxParticles: min(maxParticles, ceiling.maxParticles),
                     blurPasses: min(blurPasses, ceiling.blurPasses),
                     meshLimit: min(meshLimit, ceiling.meshLimit),
                     secondaryFPS: min(secondaryFPS, ceiling.secondaryFPS),
                     allowsExpensive: allowsExpensive && ceiling.allowsExpensive)
    }
}

/// Pure policy: callers supply monotonic sample times, not GPU utilization guesses.
/// Auto starts at High and recovers at most to High; Ultra is an explicit opt-in.
/// Environment ceilings override even manual Ultra without changing the selection.
public struct RenderQualityPolicy: Sendable {
    public enum ThermalState: Equatable, Sendable {
        case nominal, fair, serious, critical
    }

    public private(set) var selection: RenderQuality
    public private(set) var gpuMilliseconds: Double?
    public private(set) var degradationStep = 0
    public private(set) var thermalState: ThermalState = .nominal
    public private(set) var lowPowerMode = false
    private var lastSampleTime: Double?
    private var lastChangeTime: Double?
    private var evidenceStart: Double?
    private var evidenceCount = 0
    private var direction = 0

    /// Each transition changes exactly one resource, in priority order. Recovery
    /// reverses this ladder, so an effect is re-enabled before quality is restored.
    public static let autoBudgets: [RenderBudget] = {
        var budget = RenderBudget.forQuality(.high)
        var result = [budget]
        for scale in [0.75, 0.5] { budget.textureScale = scale; result.append(budget) }
        for count in [1000, 700, 400] { budget.maxParticles = count; result.append(budget) }
        for count in [1, 0] { budget.blurPasses = count; result.append(budget) }
        for limit in [32, 24, 16] { budget.meshLimit = limit; result.append(budget) }
        for fps in [60, 30] { budget.secondaryFPS = fps; result.append(budget) }
        budget.allowsExpensive = false
        result.append(budget)
        return result
    }()

    public init(selection: RenderQuality = .auto) { self.selection = selection }

    private var requestedQuality: RenderQuality {
        guard selection == .auto else { return selection }
        // Labels summarize a gradual budget; consumers must use budget's fields.
        if degradationStep <= 2 { return .high }
        if degradationStep <= 8 { return .balanced }
        return .low
    }

    private var environmentQuality: RenderQuality? {
        switch thermalState {
        case .serious, .critical: return .low
        case .fair: return .balanced
        case .nominal: return lowPowerMode ? .balanced : nil
        }
    }

    public var resolvedQuality: RenderQuality {
        guard let ceiling = environmentQuality else { return requestedQuality }
        let ranks: [RenderQuality: Int] = [.low: 0, .balanced: 1, .high: 2, .ultra: 3]
        return ranks[ceiling, default: 0] < ranks[requestedQuality, default: 0] ? ceiling : requestedQuality
    }

    public var budget: RenderBudget {
        var result = selection == .auto ? Self.autoBudgets[degradationStep] : .forQuality(selection)
        if let quality = environmentQuality { result = result.capped(by: .forQuality(quality)) }
        if thermalState == .critical { result.secondaryFPS = min(result.secondaryFPS, 15) }
        return result
    }

    public var reason: String {
        switch thermalState {
        case .critical: return "Critical thermal pressure — safety limits active"
        case .serious: return "Serious thermal pressure — safety limits active"
        case .fair: return "Elevated thermal pressure — balanced ceiling"
        case .nominal: break
        }
        if lowPowerMode { return "Low Power Mode — balanced ceiling" }
        if selection != .auto { return "Manual quality" }
        return gpuMilliseconds == nil ? "Waiting for completed GPU work" : "Adaptive GPU completion budget"
    }

    public mutating func select(_ quality: RenderQuality) {
        guard quality != selection else { return }
        self = RenderQualityPolicy(selection: quality, thermalState: thermalState, lowPowerMode: lowPowerMode)
    }

    private init(selection: RenderQuality, thermalState: ThermalState, lowPowerMode: Bool) {
        self.selection = selection
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
    }

    public mutating func refreshEnvironment(thermalState: ThermalState, lowPowerMode: Bool) {
        if self.thermalState != thermalState || self.lowPowerMode != lowPowerMode {
            clearEvidence()
        }
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
    }

    /// Accepts only actual, successful GPU durations in 10 µs...1 s. EWMA is
    /// bounded to that range, with alpha 0.15; invalid/out-of-order samples do
    /// not affect either evidence or the displayed metric. Long idle gaps break
    /// evidence streaks. Hysteresis: >12 ms for 0.5 s/8 samples to reduce,
    /// <6 ms for 5 s/30 samples to recover, with 3 s/8 s respective cooldowns.
    public mutating func recordGPUTime(_ seconds: Double, at time: Double) {
        guard seconds.isFinite, (0.00001...1).contains(seconds), time.isFinite,
              lastSampleTime.map({ time > $0 }) ?? true else { return }
        if let last = lastSampleTime, time - last > 1 { clearEvidence() }
        lastSampleTime = time
        let milliseconds = seconds * 1000
        let average = gpuMilliseconds.map { $0 + 0.15 * (milliseconds - $0) } ?? milliseconds
        gpuMilliseconds = min(1000, max(0.01, average))
        guard selection == .auto else { return }
        let nextDirection: Int
        if average > 12 { nextDirection = 1 }
        else if average < 6 { nextDirection = -1 }
        else { nextDirection = 0 }
        guard nextDirection != 0 else { clearEvidence(); return }
        if direction != nextDirection {
            clearEvidence()
            direction = nextDirection
        }
        if evidenceStart == nil { evidenceStart = time }
        evidenceCount += 1
        let reducing = nextDirection > 0
        let dwell = reducing ? 0.5 : 5.0
        let cooldown = reducing ? 3.0 : 8.0
        guard let start = evidenceStart, time - start >= dwell,
              evidenceCount >= (reducing ? 8 : 30),
              lastChangeTime.map({ time - $0 >= cooldown }) ?? true else { return }
        let step = min(Self.autoBudgets.count - 1, max(0, degradationStep + nextDirection))
        if step != degradationStep {
            degradationStep = step
            lastChangeTime = time
        }
        clearEvidence()
    }

    private mutating func clearEvidence() {
        evidenceStart = nil
        evidenceCount = 0
        direction = 0
    }
}