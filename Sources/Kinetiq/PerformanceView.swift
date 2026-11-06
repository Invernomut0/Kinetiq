// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import KinetiqCore
import SwiftUI

/// Resource limits are policy values, not measured throughput or utilization.
@MainActor
struct PerformanceView: View {
    @ObservedObject private var manager = RenderQualityManager.shared

    var body: some View {
        Form {
            Section("Render Quality") {
                Picker("Selection", selection: $manager.selection) {
                    ForEach(RenderQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Resolved quality", value: manager.resolvedQuality.title)
                Text(manager.reason).font(.callout).foregroundStyle(.secondary)
            }
            Section("Completed GPU Work") {
                if let time = manager.gpuMilliseconds {
                    LabeledContent("GPU duration (smoothed)") {
                        Text("\(time, specifier: "%.2f") ms").monospacedDigit()
                    }
                } else {
                    Label("No completed GPU sample yet", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                Text("Timings come from successful Metal command-buffer completions. No FPS or GPU utilization is inferred. The last sample remains visible while idle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Active Resource Budget") {
                LabeledContent("Intermediate texture scale", value: "\(manager.budget.textureScale.formatted(.number.precision(.fractionLength(2))))×")
                LabeledContent("Particle limit", value: "\(manager.budget.maxParticles)")
                LabeledContent("Blur passes", value: "\(manager.budget.blurPasses)")
                LabeledContent("Mesh limit per axis", value: "\(manager.budget.meshLimit)")
                LabeledContent("Secondary animation rate ceiling", value: "\(manager.budget.secondaryFPS) Hz")
                LabeledContent("Expensive effects", value: manager.budget.allowsExpensive ? "Allowed" : "Limited")
                Text("Thermal pressure and Low Power Mode can cap even a manual selection. Original captures and desktop destinations stay native; Studio preview and composition intermediates follow the texture budget.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Refresh Environment") { manager.refreshEnvironment() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}