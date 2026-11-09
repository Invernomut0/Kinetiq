// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Invernomut0Telemetry
import KinetiqCore
import XCTest
@testable import Kinetiq

/// Shared offline corpus derived from the shipped catalog and the closed product vocabulary.
enum UsagePolicyContracts {
    struct Approved {
        let usage: KinetiqUsageEvent
        let name: String
        let parameters: [String: String]

        var properties: EventProperties { parameters.mapValues { .string($0) } }
    }

    static var approved: [Approved] {
        var cases = KinetiqUsageEvent.Feature.allCases.map {
            Approved(usage: .feature($0), name: "feature_used", parameters: ["feature": $0.rawValue])
        }
        for id in LibraryEffect.all.map(\.id) + ["custom", "wobbly_classic"] {
            for trigger in KinetiqUsageEvent.Trigger.allCases {
                let parameters = ["effect_id": id, "trigger": trigger.rawValue]
                cases.append(Approved(usage: .effectSelected(effectID: id, trigger: trigger),
                                      name: "effect_selected", parameters: parameters))
                cases.append(Approved(usage: .effectPlayed(effectID: id, trigger: trigger),
                                      name: "effect_played", parameters: parameters))
            }
        }
        for id in ["off", "random"] {
            for trigger in KinetiqUsageEvent.Trigger.allCases {
                cases.append(Approved(usage: .effectSelected(effectID: id, trigger: trigger),
                    name: "effect_selected", parameters: ["effect_id": id, "trigger": trigger.rawValue]))
            }
        }
        cases += KinetiqUsageEvent.StudioAction.allCases.map {
            Approved(usage: .studio($0), name: "studio_action", parameters: ["action": $0.rawValue])
        }
        cases += KinetiqUsageEvent.SaverAction.allCases.map {
            Approved(usage: .screenSaver($0), name: "screensaver_action", parameters: ["action": $0.rawValue])
        }
        cases += RenderQuality.allCases.map {
            Approved(usage: .quality($0), name: "quality_changed", parameters: ["quality": $0.rawValue])
        }
        return cases
    }

    /// Sensitive keys and actual local metadata must not survive either adapter policy.
    static let strippedKeys: Set<String> = ["product_id", "platform", "environment", "app_version",
        "build_number", "os_version", "macos_version", "hardware_model", "hardware_architecture",
        "path", "file_path", "document_path", "window_title", "app_id", "bundle_id", "content",
        "document_name", "document_contents", "custom_effect_name", "custom_effect_id", "screenshot",
        "geo", "user_location", "ip_override", "latitude", "longitude", "city", "country",
        "session_id", "engagement_time_msec"]

    static func enriched(_ properties: EventProperties) -> EventProperties {
        var result = properties
        for key in KinetiqUsageEvent.propertyKeys where result[key] == nil { result[key] = .string(key) }
        for key in strippedKeys { result[key] = .string(key) }
        result["path"] = .string(#filePath)
        result["os_version"] = .string(ProcessInfo.processInfo.operatingSystemVersionString)
        result["platform"] = "macOS"
        return result
    }

    static var rejected: [(name: String, properties: EventProperties)] {
        let id = LibraryEffect.all[0].id
        var cases: [(name: String, properties: EventProperties)] = []
        let valid: [(String, EventProperties)] = [
            ("feature_used", ["feature": "privacy_settings"]),
            ("effect_selected", ["effect_id": .string(id), "trigger": "manual"]),
            ("effect_played", ["effect_id": .string(id), "trigger": "manual"]),
            ("studio_action", ["action": "layer_added"]),
            ("screensaver_action", ["action": "enabled"]),
            ("quality_changed", ["quality": .string(RenderQuality.allCases[0].rawValue)])
        ]
        for (name, properties) in valid {
            cases.append((name, [:]))
            for key in properties.keys {
                var missing = properties
                missing.removeValue(forKey: key)
                cases.append((name, missing))
                for value: EventValue in [.bool(true), .integer(2), .double(2), .array([.string("manual")]),
                                              .object(["value": .string("manual")]), .string(""),
                                              .string("unknown"), .string(#filePath), .string(UUID().uuidString)] {
                    var invalid = properties
                    invalid[key] = value
                    cases.append((name, invalid))
                }
            }
        }
        for name in ["effect_selected", "effect_played"] {
            for id in ["My Private Effect", "custom:" + UUID().uuidString, "catalog:unknown", "close:unknown"] {
                cases.append((name, ["effect_id": .string(id), "trigger": "manual"]))
            }
            for trigger in ["overview", "startup", "window_title", "Manual"] {
                cases.append((name, ["effect_id": .string(id), "trigger": .string(trigger)]))
            }
        }
        for id in ["off", "random"] {
            cases.append(("effect_played", ["effect_id": .string(id), "trigger": "manual"]))
        }
        for name in ["", "arbitrary_event", "screen_viewed", "error_occurred", "firebase_feature",
            "google_feature", "ga_feature", "app_launched", "app_became_active", "app_entered_background",
            "app_terminated", "session_started", "session_ended", "installation_started",
            "previous_session_interrupted"] {
            cases.append((name, ["feature": "privacy_settings", "effect_id": .string(id),
                "trigger": "manual", "action": "layer_added", "quality": .string(RenderQuality.allCases[0].rawValue)]))
        }
        cases.append(("studio_action", ["action": "enabled"]))
        cases.append(("screensaver_action", ["action": "layer_added"]))
        return cases
    }
}

final class KinetiqUsageEventTests: XCTestCase {
    func testClosedVocabularyHasSixDistinctNamesAndOnlyCategoricalKeys() {
        XCTAssertEqual(Set(UsagePolicyContracts.approved.map(\.name)), ["feature_used", "effect_selected",
            "effect_played", "studio_action", "screensaver_action", "quality_changed"])
        XCTAssertEqual(KinetiqUsageEvent.propertyKeys, ["feature", "effect_id", "trigger", "action", "quality"])
        XCTAssertEqual(Set(KinetiqUsageEvent.Feature.allCases.map(\.rawValue)), ["privacy_settings",
            "animation_studio", "effects_library", "layouts", "performance", "rules", "screen_saver"])
        XCTAssertEqual(Set(KinetiqUsageEvent.Trigger.allCases.map(\.rawValue)),
                       ["drag", "open", "close", "minimize", "manual", "layout", "maximize", "resize"])
        XCTAssertEqual(Set(KinetiqUsageEvent.StudioAction.allCases.map(\.rawValue)),
                       ["layer_added", "layer_removed", "keyframe_added", "saved", "imported", "exported"])
        XCTAssertEqual(Set(KinetiqUsageEvent.SaverAction.allCases.map(\.rawValue)),
                       ["enabled", "disabled", "preview_started"])
        for action in UsagePolicyContracts.approved {
            XCTAssertEqual(action.usage.name, action.name)
            XCTAssertEqual(action.usage.parameters, action.parameters)
            XCTAssertTrue(Set(action.parameters.keys).isSubset(of: KinetiqUsageEvent.propertyKeys))
        }
    }

    func testEveryRealLibraryEffectMapsSelectionAndPlaybackThroughActualTriggers() {
        let triggers: [(EffectTrigger, String)] = [(.drag, "drag"), (.open, "open"), (.close, "close"),
            (.minimize, "minimize"), (.overview, "layout"), (.manual, "manual")]
        let catalogIDs = Set(LibraryEffect.all.map(\.id))
        XCTAssertEqual(catalogIDs.count, LibraryEffect.all.count)
        XCTAssertEqual(KinetiqUsageEvent.playableEffectIDs, catalogIDs.union(["custom", "wobbly_classic"]))
        for effect in LibraryEffect.all {
            XCTAssertEqual(TriggerAssignment.effect(effect).usageEffectID, effect.id)
            for (trigger, expected) in triggers {
                for selected in [false, true] {
                    let usage = trigger.usageEvent(effectID: effect.id, selected: selected)
                    XCTAssertEqual(usage.name, selected ? "effect_selected" : "effect_played")
                    XCTAssertEqual(usage.parameters, ["effect_id": effect.id, "trigger": expected])
                    XCTAssertEqual(KinetiqUsageEvent.approvedParameters(name: usage.name,
                        properties: usage.parameters.mapValues { .string($0) }), usage.parameters)
                }
            }
        }
    }

    func testCustomAssignmentUsesOnlySentinelAndOffRandomAreSelectionsOnly() {
        let custom = TriggerAssignment.custom(UUID(), "Private composition")
        XCTAssertEqual(custom.usageEffectID, "custom")
        XCTAssertEqual(TriggerAssignment.classicWobble.usageEffectID, "wobbly_classic")
        XCTAssertEqual(TriggerAssignment.off.usageEffectID, "off")
        XCTAssertEqual(TriggerAssignment.random.usageEffectID, "random")
        for trigger in KinetiqUsageEvent.Trigger.allCases {
            for id in ["custom", "wobbly_classic", "off", "random"] {
                let properties: EventProperties = ["effect_id": .string(id), "trigger": .string(trigger.rawValue)]
                XCTAssertNotNil(KinetiqUsageEvent.approvedParameters(name: "effect_selected", properties: properties))
                XCTAssertEqual(KinetiqUsageEvent.approvedParameters(name: "effect_played", properties: properties) != nil,
                               id == "custom" || id == "wobbly_classic")
            }
        }
    }

    func testSharedFirebasePolicyStripsPrivateExtrasAndCoreMetadataForEveryApprovedAction() {
        for action in UsagePolicyContracts.approved {
            let properties = UsagePolicyContracts.enriched(action.properties)
            let event = TelemetryEvent(name: action.name, installationID: UUID(), properties: properties)
            XCTAssertEqual(KinetiqUsageEvent.approvedParameters(name: action.name, properties: properties), action.parameters)
            XCTAssertEqual(FirebaseAnalyticsPolicy.parameters(for: event), action.parameters)
            XCTAssertTrue(Set(action.parameters.keys).isDisjoint(with: UsagePolicyContracts.strippedKeys))
        }
    }

    func testSharedPolicyRejectsUnknownNamesIDsTriggersActionsValuesAndNonStrings() {
        for invalid in UsagePolicyContracts.rejected {
            let event = TelemetryEvent(name: invalid.name, installationID: UUID(), properties: invalid.properties)
            XCTAssertNil(KinetiqUsageEvent.approvedParameters(name: invalid.name, properties: invalid.properties), invalid.name)
            XCTAssertNil(FirebaseAnalyticsPolicy.parameters(for: event), invalid.name)
        }
    }
}