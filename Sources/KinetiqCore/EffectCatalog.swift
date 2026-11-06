// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum EffectID: String, CaseIterable, Codable, Sendable {
    case wobbly, genie, morph, fold, flip, magnet, float, shatter, explode, dissolve, burn, portal
    case depthOfField = "depth-of-field"
    case ripple
    case liquidMorph = "liquid-morph"
    case workspaceCube = "workspace-cube"
    case orbit, gravity
    case expose3D = "expose-3d"
}

public enum EffectCategory: String, CaseIterable, Codable, Sendable {
    case windowMotion, transitions, destruction, spatial, physics, workspace

    public var title: String {
        switch self {
        case .windowMotion: return "Window Motion"
        case .transitions: return "Transitions"
        case .destruction: return "Destruction"
        case .spatial: return "Spatial Effects"
        case .physics: return "Physics"
        case .workspace: return "Workspace & Overview"
        }
    }

    public var symbol: String {
        switch self {
        case .windowMotion: return "waveform.path"
        case .transitions: return "arrow.triangle.2.circlepath"
        case .destruction: return "sparkles"
        case .spatial: return "cube.transparent"
        case .physics: return "atom"
        case .workspace: return "rectangle.3.group"
        }
    }
}

public enum EffectTrigger: String, CaseIterable, Codable, Sendable {
    case manual, drag, close, minimize, open, overview

    public var title: String {
        switch self {
        case .manual: return "Manual"
        case .drag: return "Drag"
        case .close: return "Close"
        case .minimize: return "Minimize"
        case .open: return "Open"
        case .overview: return "Overview"
        }
    }
}

public enum EffectRendering: String, Codable, Sendable {
    case continuousMesh, transitionShader, particles, spatialMesh, dynamics, multiWindow

    public var title: String {
        switch self {
        case .continuousMesh: return "Continuous Mesh"
        case .transitionShader: return "Transition Shader"
        case .particles: return "Particles"
        case .spatialMesh: return "Spatial Mesh"
        case .dynamics: return "Dynamics"
        case .multiWindow: return "Captured Window Composition"
        }
    }
}

/// A bounded scalar control. Titles include units where the value is not a unitless multiplier.
/// All controls are consumed by the catalog renderer or the dynamics/overview adapter.
public struct EffectParameterSpec: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let minimum: Double
    public let maximum: Double
    public let defaultValue: Double

    public init(id: String, title: String, minimum: Double, maximum: Double, defaultValue: Double) {
        self.id = id
        self.title = title
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
    }
}

/// Describes an effect's intended rendering and fallback, not a claim of renderer availability.
public struct EffectDescriptor: Identifiable, Sendable {
    public let id: EffectID
    public let title: String
    public let category: EffectCategory
    public let submenu: String
    public let summary: String
    public let parameters: [EffectParameterSpec]
    public let triggers: [EffectTrigger]
    public let rendering: EffectRendering
    public let fallback: String
    public let expensive: Bool

    public var defaultPreset: EffectPreset { EffectPreset(effect: id) }

    /// Variants retain the same parameter schema and do not contain randomly generated timeline IDs.
    public var presets: [EffectPreset] {
        let standard = defaultPreset
        var subtle = standard
        subtle.name = "Subtle"
        subtle.parameters["amplitude"] = 0.5
        var dramatic = standard
        dramatic.name = "Dramatic"
        dramatic.parameters["amplitude"] = 1.5
        dramatic.duration = min(12, standard.duration * 1.5)
        return [standard, subtle, dramatic]
    }
}

/// Stable manifest shared by menus, preset validation and the Studio inspector.
public enum EffectCatalog {
    private static func parameter(_ id: String, _ title: String, _ min: Double,
                                  _ max: Double, _ value: Double) -> EffectParameterSpec {
        EffectParameterSpec(id: id, title: title, minimum: min, maximum: max, defaultValue: value)
    }

    private static func entry(_ id: EffectID, _ title: String, _ category: EffectCategory,
                              _ submenu: String, _ summary: String, _ rendering: EffectRendering,
                              _ triggers: [EffectTrigger], _ parameters: [EffectParameterSpec],
                              expensive: Bool = false) -> EffectDescriptor {
        EffectDescriptor(id: id, title: title, category: category, submenu: submenu, summary: summary,
                         parameters: [parameter("amplitude", "Amplitude", 0, 2, 1),
                                      parameter("speed", "Speed", 0.1, 4, 1)] + parameters,
                         triggers: [.manual] + triggers, rendering: rendering,
                         fallback: "If the rendering adapter is unavailable, leave the live window unchanged.",
                         expensive: expensive)
    }

    /// Adapter parameter semantics are explicit in the titles: angles are degrees, distances are
    /// fractions of window size unless marked in points, and rates use seconds. No native Spaces APIs.
    public static let effects: [EffectDescriptor] = [
        entry(.wobbly, "Wobbly", .windowMotion, "Elastic",
              "Deform a dragged window with a damped spring mesh.", .continuousMesh, [.drag], [
                parameter("stiffness", "Spring Stiffness", 1, 10, 3.8),
                parameter("friction", "Spring Friction", 1, 10, 3.5)]),
        entry(.genie, "Genie", .transitions, "Minimize / Restore",
              "Taper a captured window toward its minimize target or reverse the transition.",
              .continuousMesh, [.minimize, .open], [
                parameter("curvature", "Taper Curvature", 0, 1, 0.6)]),
        entry(.morph, "Morph", .transitions, "Transform",
              "Interpolate a captured window between source and destination geometry.",
              .continuousMesh, [.open, .minimize], [
                parameter("roundness", "Corner Radius / Short Edge", 0, 0.5, 0.1)]),
        entry(.fold, "Fold", .spatial, "3D Transform",
              "Fold a captured window around a central hinge.", .spatialMesh, [.close, .open], [
                parameter("angle", "Hinge Angle (degrees)", 0, 180, 90)]),
        entry(.flip, "Flip", .spatial, "3D Transform",
              "Rotate a captured window around its vertical axis.", .spatialMesh, [.open, .close], [
                parameter("angle", "Rotation Angle (degrees)", -180, 180, 180)]),
        entry(.magnet, "Magnet", .physics, "Attraction & Snapping",
              "Attract a dragged window toward a nearby snapping target.", .dynamics, [.drag], [
                parameter("radius", "Attraction Radius (points)", 10, 600, 160),
                parameter("strength", "Attraction Strength", 0, 2, 1)]),
        entry(.float, "Float", .windowMotion, "Ambient Motion",
              "Apply a gentle periodic offset to a captured window.", .continuousMesh, [.drag, .open], [
                parameter("distance", "Travel / Window Height", 0, 0.25, 0.03),
                parameter("frequency", "Oscillations per Second", 0.1, 3, 0.5)]),
        entry(.shatter, "Shatter", .destruction, "Fragmentation",
              "Break a captured window into falling fragments.", .particles, [.close], [
                parameter("fragments", "Fragment Count", 4, 256, 64),
                parameter("spread", "Spread / Window Width", 0, 2, 0.6)], expensive: true),
        entry(.explode, "Explode", .destruction, "Fragmentation",
              "Propel captured window fragments outward from the center.", .particles, [.close], [
                parameter("fragments", "Fragment Count", 4, 256, 96),
                parameter("spread", "Spread / Window Width", 0, 2, 1.2)], expensive: true),
        entry(.dissolve, "Dissolve", .destruction, "Dissolution",
              "Remove a captured window through a spatial noise threshold.", .transitionShader, [.close, .open], [
                parameter("scale", "Noise Cells per Short Edge", 2, 100, 24),
                parameter("softness", "Threshold Softness", 0, 1, 0.15)]),
        entry(.burn, "Burn", .destruction, "Dissolution",
              "Advance a luminous burn edge across a captured window.", .transitionShader, [.close], [
                parameter("edgeWidth", "Burn Edge / Window Height", 0.001, 0.2, 0.04)], expensive: true),
        entry(.portal, "Portal", .spatial, "Distortion",
              "Warp a captured window toward a radial portal.", .transitionShader, [.open, .close], [
                parameter("radius", "Portal Radius / Short Edge", 0.05, 1, 0.5),
                parameter("twist", "Twist (degrees)", -360, 360, 180)]),
        entry(.depthOfField, "DOF", .spatial, "Depth & Lighting",
              "Defocus captured windows away from a selected focal depth.", .spatialMesh, [.overview], [
                parameter("focus", "Normalized Focal Depth", 0, 1, 0.5),
                parameter("blur", "Maximum Blur (points)", 0, 40, 12)], expensive: true),
        entry(.ripple, "Ripple", .transitions, "Distortion",
              "Send a decaying radial wave through a window mesh.", .continuousMesh, [.drag, .open], [
                parameter("wavelength", "Wavelength (points)", 20, 600, 150),
                parameter("decay", "Decay Time (seconds)", 0.05, 3, 0.45)]),
        entry(.liquidMorph, "Liquid Morph", .transitions, "Distortion",
              "Distort a captured window with a refractive liquid transition.", .transitionShader, [.open, .close], [
                parameter("viscosity", "Normalized Viscosity", 0, 1, 0.65),
                parameter("refraction", "Refraction Strength", 0, 2, 0.8)], expensive: true),
        entry(.workspaceCube, "Cube", .workspace, "Workspace Navigation",
              "Arrange captured windows from the current Space on a cube-like overview; does not switch native Spaces.",
              .multiWindow, [.overview], [
                parameter("angle", "Overview Rotation (degrees)", -180, 180, 45),
                parameter("perspective", "Perspective Strength", 0, 1, 0.6)], expensive: true),
        entry(.orbit, "Orbit", .workspace, "Window Arrangement",
              "Arrange captured windows around an elliptical overview path.", .multiWindow, [.overview], [
                parameter("radius", "Orbit Radius / Viewport Short Edge", 0.1, 1, 0.4),
                parameter("angle", "Orbit Rotation (degrees)", -180, 180, 0)], expensive: true),
        entry(.gravity, "Gravity", .physics, "Forces & Dynamics",
              "Apply downward acceleration and bounded restitution to captured windows.", .dynamics, [.drag], [
                parameter("acceleration", "Acceleration (points / second squared)", 0, 3000, 980),
                parameter("restitution", "Bounce Restitution", 0, 1, 0.6)]),
        entry(.expose3D, "Exposé 3D", .workspace, "Window Overview",
              "Spread captured windows from the current Space into a tilted overview.", .multiWindow, [.overview], [
                parameter("angle", "Overview Tilt (degrees)", 0, 75, 25),
                parameter("spacing", "Spacing / Window Width", 0, 1, 0.15)], expensive: true),
    ]

    /// The manifest is exhaustive; unknown raw IDs fail Codable decoding before reaching this API.
    public static func descriptor(_ id: EffectID) -> EffectDescriptor {
        // A missing entry is a programmer error, never a user-input fallback to a different effect.
        guard let descriptor = effects.first(where: { $0.id == id }) else {
            preconditionFailure("Missing effect descriptor: \(id.rawValue)")
        }
        return descriptor
    }
}