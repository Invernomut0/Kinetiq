// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import KinetiqCore
import SwiftUI

/// Originals use their real engines and shared historical controls, not aliases
/// to similarly named Studio effects or incompatible schema-1 presets.
@MainActor
struct OriginalEffectDetailView: View {
    let effect: LibraryEffect
    @ObservedObject var model: SetupModel
    @ObservedObject private var store = CatalogStore.shared
    @State private var tab: EffectDetailTab = .preview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(effect.category.title) / \(effect.submenu)").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(effect.title).font(.title2.bold())
                Text(effect.badge).font(.caption).foregroundStyle(.secondary)
            }
            Text("The original rendering engine, with your existing settings and native triggers.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Detail", selection: $tab) {
                ForEach(EffectDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if let error = model.effectError { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            assignmentButtons
        }
        .padding(18)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .preview:
            OriginalEffectPreview(effect: effect, settings: model.settings)
        case .parameters:
            VStack(alignment: .leading, spacing: 16) {
                if case .entrance = effect {
                    Text("Original entrances share the spring/mesh settings on Physics. They replay the original jelly model, not the Studio Ripple or Wobbly shader.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open Physics Settings") { model.requestedPage = .physics }
                } else {
                    HStack {
                        Text("Duration multiplier")
                        Spacer()
                        Text("\(model.settings.closeDuration, specifier: "%.2f")×").monospacedDigit()
                    }
                    Slider(value: model.binding({ model.settings.closeDuration }, { model.settings.closeDuration = $0 }),
                           in: Settings.closeSpeedRange)
                        .accessibilityLabel("Original duration multiplier")
                    Text("Range 0.25–3×, default 1×. This existing control is shared by original close and minimize effects; changes apply immediately. Shader-specific material values retain their original compiled defaults.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .triggers:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(effect.triggers, id: \.self) { trigger in
                    LabeledContent(trigger.title, value: selected(trigger) ? "Active" : "Not assigned")
                    if let owner = store.assigned(to: trigger) {
                        Text("\(EffectCatalog.descriptor(owner.effect).title) currently owns \(trigger.title). Activating this original releases only that assignment; its preset and tracks are preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Close runs only after a real close. Open uses the original entrance. Minimize intercepts the yellow button only; ⌘M remains native. Existing per-app close overrides and exclusions remain in Rules.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Use Window Trigger Assignments below for Off or Random. No assignment is changed merely by opening this page or its preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .performance:
            VStack(alignment: .leading, spacing: 12) {
                Text(effect.badge).font(.headline)
                Text("Preview uses the original shader, mesh deformer or particle-fluid simulation. Native trigger capture/restoration and quality limits remain in their existing engine adapters.")
                    .font(.callout).foregroundStyle(.secondary)
                PerformanceView()
            }
        case .reset:
            VStack(alignment: .leading, spacing: 16) {
                Text("Shared original settings").font(.headline)
                Text("Original effects do not use Studio JSON presets. Resetting the duration affects original close and minimize effects together; it does not change trigger choices, per-app rules or exclusions.")
                    .foregroundStyle(.secondary)
                Button("Reset Shared Duration to 1×") { model.settings.closeDuration = 1; model.refresh() }
                if case .entrance = effect {
                    Button("Open Physics Settings") { model.requestedPage = .physics }
                }
            }
        }
    }

    private var assignmentButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack { buttons }
            VStack(alignment: .leading) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(effect.triggers, id: \.self) { trigger in
            Button(selected(trigger) ? "Active for \(trigger.title)" : "Use for \(trigger.title)") {
                model.applyOriginalEffect(effect, trigger: trigger)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected(trigger))
        }
    }

    private func selected(_ trigger: EffectTrigger) -> Bool {
        OriginalEffectAssignment.isSelected(effect, trigger: trigger, settings: model.settings, store: store)
    }
}