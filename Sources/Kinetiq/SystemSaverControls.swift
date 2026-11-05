// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Explicit opt-in before changing macOS preferences or saving private desktop content.
struct SystemSaverControls: View {
    @ObservedObject var manager: SystemScreenSaver
    let settings: Settings
    @State private var confirmingEnable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Use as macOS Screen Saver", isOn: Binding(get: { manager.hasSelection }, set: { enabled in
                if enabled { confirmingEnable = true } else { Task { await manager.setEnabled(false) } }
            }))
            .disabled(manager.isChanging)
            if manager.isChanging {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Applying system screen saver…").foregroundStyle(.secondary)
                }
            }
            Label(manager.isSelected ? "Kinetiq is the default macOS screen saver" : "Not selected as the macOS screen saver",
                  systemImage: manager.isSelected ? "checkmark.circle.fill" : "display")
                .foregroundStyle(manager.isSelected ? .green : .secondary)
            if manager.hasSelection, !manager.isSelected {
                Text("Selected on some displays or Spaces only. Disable, then enable to select it everywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("macOS starts after (min)") {
                HStack {
                    Slider(value: Binding(get: { Double(settings.chaosIdleMinutes) }, set: { manager.setIdleMinutes(Int($0.rounded())) }),
                           in: Double(Settings.chaosIdleRange.lowerBound)...Double(Settings.chaosIdleRange.upperBound), step: 1)
                    Text("\(settings.chaosIdleMinutes)").monospacedDigit().frame(width: 28)
                }.frame(width: 240)
            }
            .disabled(manager.isChanging)
            HStack {
                Button("Open macOS Screen Saver Settings") { manager.openSystemSettings() }
                Button("Refresh System Status") { manager.refreshStatus() }
            }
            if let error = manager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = manager.capturedAt {
                Text("Desktop scene prepared \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("The system module uses a private local desktop snapshot, refreshed shortly before inactivity while Kinetiq is running. It can show private window content on the lock screen. Disabling restores the previous screen saver and deletes the snapshot. Your wallpaper and password policy are not changed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { manager.refreshStatus() }
        .alert("Make Kinetiq the macOS screen saver?", isPresented: $confirmingEnable) {
            Button("Cancel", role: .cancel) { }
            Button("Enable System Screen Saver") { Task { await manager.setEnabled(true) } }
        } message: {
            Text("Kinetiq will install its native module for your user, select it on every display and Space, and set the macOS inactivity delay. A private local snapshot of your desktop will be saved and may be visible on the lock screen. The wallpaper agent restarts briefly. Disabling restores the previous screen saver and removes the snapshot.")
        }
    }
}