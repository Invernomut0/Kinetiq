// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Invernomut0Telemetry
import KinetiqCore

/// Closed product vocabulary. No document, window, application or custom-effect identity is accepted.
enum KinetiqUsageEvent {
    enum Feature: String, CaseIterable {
        case privacySettings = "privacy_settings"
        case animationStudio = "animation_studio"
        case effectsLibrary = "effects_library"
        case layouts, performance, rules
        case screenSaver = "screen_saver"
    }

    enum Trigger: String, CaseIterable {
        case drag, open, close, minimize, manual, layout, maximize, resize
    }

    enum StudioAction: String, CaseIterable {
        case layerAdded = "layer_added"
        case layerRemoved = "layer_removed"
        case keyframeAdded = "keyframe_added"
        case saved, imported, exported
    }

    enum SaverAction: String, CaseIterable {
        case enabled, disabled
        case previewStarted = "preview_started"
    }

    case feature(Feature)
    case effectPlayed(effectID: String, trigger: Trigger)
    case effectSelected(effectID: String, trigger: Trigger)
    case studio(StudioAction)
    case screenSaver(SaverAction)
    case quality(RenderQuality)

    static let propertyKeys: Set<String> = ["feature", "effect_id", "trigger", "action", "quality"]
    static let playableEffectIDs = Set(LibraryEffect.all.map(\.id)).union(["custom", "wobbly_classic"])

    var name: String {
        switch self {
        case .feature: return "feature_used"
        case .effectPlayed: return "effect_played"
        case .effectSelected: return "effect_selected"
        case .studio: return "studio_action"
        case .screenSaver: return "screensaver_action"
        case .quality: return "quality_changed"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .feature(let feature): return ["feature": feature.rawValue]
        case .effectPlayed(let id, let trigger), .effectSelected(let id, let trigger):
            return ["effect_id": id, "trigger": trigger.rawValue]
        case .studio(let action): return ["action": action.rawValue]
        case .screenSaver(let action): return ["action": action.rawValue]
        case .quality(let quality): return ["quality": quality.rawValue]
        }
    }

    /// Validate again at each provider boundary; unknown extra properties never enter the payload.
    static func approvedParameters(name: String, properties: EventProperties) -> [String: String]? {
        func string(_ key: String) -> String? {
            guard case .string(let value) = properties[key] else { return nil }
            return value
        }
        switch name {
        case "feature_used":
            guard let value = string("feature"), Feature(rawValue: value) != nil else { return nil }
            return ["feature": value]
        case "effect_played", "effect_selected":
            guard let id = string("effect_id"), let trigger = string("trigger"),
                  Trigger(rawValue: trigger) != nil else { return nil }
            let permitted = playableEffectIDs.contains(id) || (name == "effect_selected" && ["off", "random"].contains(id))
            guard permitted else { return nil }
            return ["effect_id": id, "trigger": trigger]
        case "studio_action":
            guard let action = string("action"), StudioAction(rawValue: action) != nil else { return nil }
            return ["action": action]
        case "screensaver_action":
            guard let action = string("action"), SaverAction(rawValue: action) != nil else { return nil }
            return ["action": action]
        case "quality_changed":
            guard let quality = string("quality"), RenderQuality(rawValue: quality) != nil else { return nil }
            return ["quality": quality]
        default: return nil
        }
    }
}