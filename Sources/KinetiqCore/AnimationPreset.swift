// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum AnimationCurve: String, CaseIterable, Codable, Sendable {
    case linear, easeIn, easeOut, easeInOut, spring

    /// Bounded easing; NaN means the start, infinities clamp to their corresponding endpoint.
    /// Spring is a normalized damped oscillation, clipped to avoid exceeding parameter bounds.
    public func value(at progress: Double) -> Double {
        let t = progress.isNaN ? 0 : min(1, max(0, progress))
        if t == 0 || t == 1 { return t }
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInOut: return t * t * (3 - 2 * t)
        case .spring:
            return min(1, max(0, (1 - exp(-6 * t) * cos(8 * t)) / (1 - exp(-6) * cos(8))))
        }
    }
}

/// Stable, inspectable validation failures. Paths identify the invalid field in a preset or document.
public enum AnimationValidationError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidValue(path: String, reason: String)
    case unknownParameter(String)
    case limitExceeded(path: String, maximum: Int)
    case unknownField(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Unsupported animation schema version: \(version)."
        case .invalidValue(let path, let reason): return "Invalid \(path): \(reason)."
        case .unknownParameter(let parameter): return "Unknown effect parameter: \(parameter)."
        case .limitExceeded(let path, let maximum): return "\(path) exceeds the limit of \(maximum)."
        case .unknownField(let field): return "Unknown JSON field: \(field)."
        }
    }
}

/// Pure value types intentionally contain no undo manager, rendering resources or UI state.
public struct AnimationKeyframe: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// Position within a preset, normalized to 0...1 (not seconds).
    public var time: Double
    public var value: Double
    /// Easing for the segment leaving this keyframe. The final keyframe's curve is unused.
    public var curve: AnimationCurve

    public init(time: Double, value: Double, curve: AnimationCurve = .easeInOut) {
        id = UUID()
        self.time = time
        self.value = value
        self.curve = curve
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, time, value, curve }

    public init(from decoder: Decoder) throws {
        try strictFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        time = try c.decode(Double.self, forKey: .time)
        value = try c.decode(Double.self, forKey: .value)
        curve = try c.decode(AnimationCurve.self, forKey: .curve)
        try bounded(time, in: 0...1, path: "keyframe.time")
        guard value.isFinite else { throw invalid("keyframe.value", "must be finite") }
    }
}

public struct AnimationTrack: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var parameter: String
    /// Strictly increasing normalized times. Empty tracks use the preset's static value.
    public var keyframes: [AnimationKeyframe]
    public var muted: Bool

    public init(parameter: String, keyframes: [AnimationKeyframe] = [], muted: Bool = false) {
        id = UUID()
        self.parameter = parameter
        self.keyframes = keyframes
        self.muted = muted
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, parameter, keyframes, muted }

    public init(from decoder: Decoder) throws {
        try strictFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        parameter = try c.decode(String.self, forKey: .parameter)
        keyframes = try limitedArray(c, key: .keyframes, maximum: EffectPreset.maximumKeyframes)
        muted = try c.decode(Bool.self, forKey: .muted)
    }
}

public struct EffectPreset: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumTracks = 64
    public static let maximumKeyframes = 128
    public static let durationRange = 0.1...12.0

    public var schemaVersion: Int = 1
    public var effect: EffectID
    public var name: String
    public var duration: Double
    public var curve: AnimationCurve
    public var trigger: EffectTrigger
    public var parameters: [String: Double]
    public var tracks: [AnimationTrack]

    public init(effect: EffectID) {
        let descriptor = EffectCatalog.descriptor(effect)
        self.effect = effect
        name = "Default"
        duration = 1
        curve = .easeInOut
        trigger = .manual
        parameters = Dictionary(uniqueKeysWithValues: descriptor.parameters.map { ($0.id, $0.defaultValue) })
        tracks = []
    }

    /// Validates without mutating, sorting or silently discarding data. Sparse parameters use defaults.
    /// Duplicate parameter tracks are rejected even when muted, making unmuting unambiguous.
    public func validated() throws -> EffectPreset {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AnimationValidationError.unsupportedVersion(schemaVersion)
        }
        try validName(name, path: "preset.name")
        try bounded(duration, in: Self.durationRange, path: "preset.duration")
        let descriptor = EffectCatalog.descriptor(effect)
        guard descriptor.triggers.contains(trigger) else {
            throw invalid("preset.trigger", "not supported by \(effect.rawValue)")
        }
        let specs = Dictionary(uniqueKeysWithValues: descriptor.parameters.map { ($0.id, $0) })
        for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
            guard let spec = specs[key] else { throw AnimationValidationError.unknownParameter(key) }
            try bounded(value, in: spec.minimum...spec.maximum, path: "parameters.\(key)")
        }
        try limit(tracks.count, maximum: Self.maximumTracks, path: "tracks")
        var trackIDs = Set<UUID>()
        var parameterIDs = Set<String>()
        var keyIDs = Set<UUID>()
        for track in tracks {
            guard let spec = specs[track.parameter] else {
                throw AnimationValidationError.unknownParameter(track.parameter)
            }
            guard trackIDs.insert(track.id).inserted else { throw invalid("track.id", "must be unique") }
            guard parameterIDs.insert(track.parameter).inserted else {
                throw invalid("track.parameter", "must have only one track per parameter")
            }
            try limit(track.keyframes.count, maximum: Self.maximumKeyframes, path: "keyframes")
            var previousTime = -Double.infinity
            for key in track.keyframes {
                guard keyIDs.insert(key.id).inserted else { throw invalid("keyframe.id", "must be unique") }
                try bounded(key.time, in: 0...1, path: "keyframe.time")
                try bounded(key.value, in: spec.minimum...spec.maximum, path: "keyframe.value")
                guard key.time > previousTime else {
                    throw invalid("keyframe.time", "must be strictly increasing")
                }
                previousTime = key.time
            }
        }
        return self
    }

    /// Samples seconds relative to the preset, independently of wall time, frame rate or UI undo.
    /// Holds the first/last key outside their interval. Muted/empty tracks use the static value.
    /// The preset curve is playback metadata, not a second time warp applied here.
    /// Segment interpolation uses each outgoing key's curve.
    /// Unknown parameters return zero. Call validated() before playback of externally edited values.
    public func value(_ parameter: String, at seconds: Double) -> Double {
        guard let spec = EffectCatalog.descriptor(effect).parameters.first(where: { $0.id == parameter }) else {
            return 0
        }
        let rawBase = parameters[parameter] ?? spec.defaultValue
        let base = rawBase.isFinite ? min(spec.maximum, max(spec.minimum, rawBase)) : spec.defaultValue
        guard let track = tracks.first(where: { $0.parameter == parameter && !$0.muted }),
              let first = track.keyframes.first, let last = track.keyframes.last,
              duration.isFinite, duration > 0 else { return base }
        let time = seconds.isNaN ? 0 : min(1, max(0, seconds / duration))
        func safe(_ value: Double) -> Double {
            value.isFinite ? min(spec.maximum, max(spec.minimum, value)) : base
        }
        if time <= first.time { return safe(first.value) }
        if time >= last.time { return safe(last.value) }
        for (left, right) in zip(track.keyframes, track.keyframes.dropFirst()) {
            if time >= left.time && time < right.time {
                let progress = left.curve.value(at: (time - left.time) / (right.time - left.time))
                return safe(left.value + (right.value - left.value) * progress)
            }
        }
        return base
    }

    public func encoded() throws -> Data { try animationEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> EffectPreset {
        try limit(data.count, maximum: maximumAnimationJSONBytes, path: "JSON bytes")
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, effect, name, duration, curve, trigger, parameters, tracks
    }

    public init(from decoder: Decoder) throws {
        try strictFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AnimationValidationError.unsupportedVersion(schemaVersion)
        }
        effect = try c.decode(EffectID.self, forKey: .effect)
        name = try c.decode(String.self, forKey: .name)
        duration = try c.decode(Double.self, forKey: .duration)
        curve = try c.decode(AnimationCurve.self, forKey: .curve)
        trigger = try c.decode(EffectTrigger.self, forKey: .trigger)
        parameters = try c.decode([String: Double].self, forKey: .parameters)
        tracks = try limitedArray(c, key: .tracks, maximum: Self.maximumTracks)
        self = try validated()
    }

    public func encode(to encoder: Encoder) throws {
        _ = try validated()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(effect, forKey: .effect)
        try c.encode(name, forKey: .name)
        try c.encode(duration, forKey: .duration)
        try c.encode(curve, forKey: .curve)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(tracks, forKey: .tracks)
    }
}

public struct StudioLayer: Identifiable, Codable, Equatable, Sendable {
    /// Discovery-ID prefixes of the built-in engines a layer may reference. Liquid is a
    /// desktop-wide simulation and cannot be sampled per frame, so it is not a layer.
    public static let builtinPrefixes = ["close:", "open:", "minimize:"]

    public var id: UUID
    public var name: String
    /// Catalog effect, parameters and tracks. For a built-in layer only `duration` and `curve`
    /// are used: they time the original engine, whose own parameters are compiled defaults.
    public var preset: EffectPreset
    /// Offset in document seconds. A layer must fit entirely inside the document, even if disabled.
    public var start: Double
    public var enabled: Bool
    /// A built-in engine (for example `close:incinerate`) instead of the catalog `preset.effect`.
    public var builtin: String?
    /// Plays the layer backwards, e.g. a close shader as an entrance. Schema 2.
    public var reversed: Bool

    public init(preset: EffectPreset, start: Double = 0) {
        id = UUID()
        name = EffectCatalog.descriptor(preset.effect).title
        self.preset = preset
        self.start = start
        enabled = true
        builtin = nil
        reversed = false
    }

    /// A layer that plays an original engine for `duration` seconds.
    public init(builtin: String, name: String, duration: Double, start: Double = 0) {
        var timing = EffectPreset(effect: .dissolve)
        timing.name = name
        timing.duration = min(EffectPreset.durationRange.upperBound, max(EffectPreset.durationRange.lowerBound, duration))
        timing.curve = .linear
        self.init(preset: timing, start: start)
        self.name = name
        self.builtin = builtin
    }

    public var duration: Double { preset.duration }
    public var end: Double { start + preset.duration }
    public var isBuiltin: Bool { builtin != nil }

    /// Normalized playback position at document `time`, after the layer's curve and direction.
    public func progress(at time: Double) -> Double {
        let local = (time - start) / max(0.000001, preset.duration)
        let clock = preset.curve.value(at: local)
        return reversed ? 1 - clock : clock
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, preset, start, enabled, builtin, reversed }

    public init(from decoder: Decoder) throws {
        try strictFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        preset = try c.decode(EffectPreset.self, forKey: .preset)
        start = try c.decode(Double.self, forKey: .start)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        builtin = try c.decodeIfPresent(String.self, forKey: .builtin)
        reversed = try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? false
        try validName(name, path: "layer.name")
        try bounded(start, in: 0...StudioDocument.maximumDuration, path: "layer.start")
        try Self.validBuiltin(builtin)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(preset, forKey: .preset)
        try c.encode(start, forKey: .start)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(builtin, forKey: .builtin)
        try c.encode(reversed, forKey: .reversed)
    }

    static func validBuiltin(_ builtin: String?) throws {
        guard let builtin else { return }
        try limit(builtin.utf8.count, maximum: 128, path: "layer.builtin")
        guard let prefix = builtinPrefixes.first(where: { builtin.hasPrefix($0) }), builtin.count > prefix.count,
              builtin.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == ":" }) else {
            throw invalid("layer.builtin", "must be close:, open: or minimize: followed by an effect identifier")
        }
    }
}

public struct StudioDocument: Codable, Equatable, Sendable {
    /// Version 2 adds built-in and reversed layers; version 1 documents still decode.
    public static let currentSchemaVersion = 2
    public static let supportedSchemaVersions = 1...2
    public static let maximumDuration = 60.0
    public static let maximumLayers = 32

    public var schemaVersion: Int = StudioDocument.currentSchemaVersion
    public var name: String
    public var duration: Double
    public var layers: [StudioLayer]

    public init(name: String = "Untitled", duration: Double = 3, layers: [StudioLayer] = []) {
        self.name = name
        self.duration = duration
        self.layers = layers
    }

    public func validated() throws -> StudioDocument {
        guard Self.supportedSchemaVersions.contains(schemaVersion) else {
            throw AnimationValidationError.unsupportedVersion(schemaVersion)
        }
        try validName(name, path: "document.name")
        try bounded(duration, in: 0.1...Self.maximumDuration, path: "document.duration")
        try limit(layers.count, maximum: Self.maximumLayers, path: "layers")
        var ids = Set<UUID>()
        for layer in layers {
            guard ids.insert(layer.id).inserted else { throw invalid("layer.id", "must be unique") }
            try validName(layer.name, path: "layer.name")
            _ = try layer.preset.validated()
            try StudioLayer.validBuiltin(layer.builtin)
            try bounded(layer.start, in: 0...duration, path: "layer.start")
            // Permit binary rounding at an exact decimal boundary (for example 0.2 + 0.1 == 0.3).
            guard layer.start + layer.preset.duration <= duration + 4 * duration.ulp else {
                throw invalid("layer.start", "layer must end within the document duration")
            }
        }
        return self
    }

    public func encoded() throws -> Data { try animationEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> StudioDocument {
        try limit(data.count, maximum: maximumAnimationJSONBytes, path: "JSON bytes")
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, name, duration, layers }

    public init(from decoder: Decoder) throws {
        try strictFields(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard Self.supportedSchemaVersions.contains(version) else {
            throw AnimationValidationError.unsupportedVersion(version)
        }
        name = try c.decode(String.self, forKey: .name)
        duration = try c.decode(Double.self, forKey: .duration)
        layers = try limitedArray(c, key: .layers, maximum: Self.maximumLayers)
        // Version 1 had no built-in layers; reject them so an old reader's contract holds.
        if version == 1, layers.contains(where: { $0.builtin != nil || $0.reversed }) {
            throw AnimationValidationError.unsupportedVersion(version)
        }
        // Upgraded in memory; re-encoding writes the current version.
        schemaVersion = Self.currentSchemaVersion
        self = try validated()
    }

    public func encode(to encoder: Encoder) throws {
        _ = try validated()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(name, forKey: .name)
        try c.encode(duration, forKey: .duration)
        try c.encode(layers, forKey: .layers)
    }
}

// MARK: - Strict serialization and shared validation

private let maximumAnimationJSONBytes = 32 * 1024 * 1024

private func invalid(_ path: String, _ reason: String) -> AnimationValidationError {
    .invalidValue(path: path, reason: reason)
}

private func bounded(_ value: Double, in range: ClosedRange<Double>, path: String) throws {
    guard value.isFinite, range.contains(value) else {
        throw invalid(path, "must be finite and in \(range.lowerBound)...\(range.upperBound)")
    }
}

private func limit(_ count: Int, maximum: Int, path: String) throws {
    guard count <= maximum else { throw AnimationValidationError.limitExceeded(path: path, maximum: maximum) }
}

private func validName(_ name: String, path: String) throws {
    try limit(name.utf8.count, maximum: 256, path: path)
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        throw invalid(path, "must be nonempty and contain no control characters")
    }
}

private struct FieldKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func strictFields(_ decoder: Decoder, allowed: [String]) throws {
    let container = try decoder.container(keyedBy: FieldKey.self)
    let allowed = Set(allowed)
    for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
        guard allowed.contains(key.stringValue) else {
            throw AnimationValidationError.unknownField(key.stringValue)
        }
    }
}

/// Checks declared array size before allocating model elements and also bounds streaming decoders.
private func limitedArray<T: Decodable, K: CodingKey>(_ container: KeyedDecodingContainer<K>,
                                                      key: K, maximum: Int) throws -> [T] {
    var array = try container.nestedUnkeyedContainer(forKey: key)
    if let count = array.count { try limit(count, maximum: maximum, path: key.stringValue) }
    var result: [T] = []
    while !array.isAtEnd {
        try limit(result.count + 1, maximum: maximum, path: key.stringValue)
        result.append(try array.decode(T.self))
    }
    return result
}

private func animationEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}