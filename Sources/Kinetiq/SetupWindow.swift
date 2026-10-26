// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
import SwiftUI

/// Bridges `Settings` (UserDefaults) to SwiftUI: every binding writes through and refreshes the view.
@MainActor
final class SetupModel: ObservableObject {
    let settings: Settings
    private let closeEffectChanged: () -> Void

    init(settings: Settings, closeEffectChanged: @escaping () -> Void) {
        self.settings = settings
        self.closeEffectChanged = closeEffectChanged
    }

    func refresh() { objectWillChange.send() }

    func binding<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { [weak self] value in
            set(value)
            self?.refresh()
        })
    }

    func physicsBinding(_ get: @escaping (KinetiqSettings) -> Float,
                        _ set: @escaping (inout KinetiqSettings, Float) -> Void) -> Binding<Double> {
        binding({ Double(get(self.settings.physics)) }, { value in
            var physics = self.settings.physics
            set(&physics, Float(value))
            self.settings.physics = physics
            // Moving a physics slider switches the preset to "Custom", like the GNOME extension does.
            self.settings.preset = .custom
        })
    }

    func selectCloseEffect(_ raw: String) {
        settings.closeEffect = CloseEffectChoice(rawValue: raw)
        closeEffectChanged()
        refresh()
    }

    func resetToDefaults() {
        settings.resetToDefaults()
        closeEffectChanged()
        refresh()
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        let settings = model.settings
        Form {
            Section("Wobble") {
                Picker("Preset", selection: model.binding({ settings.preset }, { settings.preset = $0 })) {
                    ForEach(WobblePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SliderRow(title: "Friction", value: model.physicsBinding({ $0.friction }, { $0.friction = $1 }),
                          range: Settings.frictionRange, decimals: 1)
                SliderRow(title: "Spring", value: model.physicsBinding({ $0.spring }, { $0.spring = $1 }),
                          range: Settings.springRange, decimals: 1)
                SliderRow(title: "Speedup", value: model.physicsBinding({ $0.speedup }, { $0.speedup = $1 }),
                          range: Settings.speedupRange, decimals: 1)
                SliderRow(title: "Mass", value: model.physicsBinding({ $0.mass }, { $0.mass = $1 }),
                          range: Settings.massRange, decimals: 0)
                SliderRow(title: "Tiles X",
                          value: model.binding({ Double(settings.tilesX) }, { settings.tilesX = Int($0) }),
                          range: Settings.tilesRange, decimals: 0)
                SliderRow(title: "Tiles Y",
                          value: model.binding({ Double(settings.tilesY) }, { settings.tilesY = Int($0) }),
                          range: Settings.tilesRange, decimals: 0)
                Toggle("Effect on Maximize",
                       isOn: model.binding({ settings.maximizeEffect }, { settings.maximizeEffect = $0 }))
                Toggle("Effect on Resize",
                       isOn: model.binding({ settings.resizeEffect }, { settings.resizeEffect = $0 }))
                Toggle("Shadow", isOn: model.binding({ settings.shadow }, { settings.shadow = $0 }))
            }

            Section("Close Effect") {
                Picker("Effect", selection: model.binding({ settings.closeEffect.rawValue }, { model.selectCloseEffect($0) })) {
                    Text("Off").tag(CloseEffectChoice.off.rawValue)
                    Text("Random").tag(CloseEffectChoice.random.rawValue)
                    Divider()
                    ForEach(CloseEffect.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                SliderRow(title: "Duration",
                          value: model.binding({ settings.closeDuration }, { settings.closeDuration = $0 }),
                          range: Settings.closeSpeedRange, decimals: 2)
            }

            Section("Permissions") {
                PermissionRow(title: "Accessibility", granted: Permissions.accessibilityGranted(prompt: false)) {
                    Permissions.openPrivacySettings("Privacy_Accessibility")
                }
                PermissionRow(title: "Screen Recording", granted: Permissions.screenCaptureGranted) {
                    CGRequestScreenCaptureAccess()
                    Permissions.openPrivacySettings("Privacy_ScreenCapture")
                }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) { model.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

private struct SliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let decimals: Int

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(decimals)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: 240)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let grant: () -> Void

    var body: some View {
        LabeledContent(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant…", action: grant)
            }
        }
    }
}

/// Owns the detached Setup window; reopening brings the same window forward.
@MainActor
final class SetupWindowController {
    private let model: SetupModel
    private var window: NSWindow?

    init(settings: Settings, closeEffectChanged: @escaping () -> Void) {
        model = SetupModel(settings: settings, closeEffectChanged: closeEffectChanged)
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SetupView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Kinetiq Setup"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
