// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import KinetiqEffects
import SwiftUI
import UniformTypeIdentifiers

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

    func selectOpenEffect(_ raw: String) {
        settings.openEffect = OpenEffectChoice(rawValue: raw)
        closeEffectChanged()
        refresh()
    }

    func selectMinimizeEffect(_ raw: String) {
        settings.minimizeEffect = MinimizeEffectChoice(rawValue: raw)
        DockGenie.sync(enabled: settings.minimizeEffect != .off)
        closeEffectChanged()
        refresh()
    }

    func resetToDefaults() {
        settings.resetToDefaults()
        DockGenie.sync(enabled: settings.minimizeEffect != .off)
        closeEffectChanged()
        refresh()
    }

    func addExclusion(_ bundleID: String) {
        guard !settings.excludedApps.contains(bundleID) else { return }
        settings.excludedApps.append(bundleID)
        refresh()
    }

    func removeExclusion(_ bundleID: String) {
        settings.excludedApps.removeAll { $0 == bundleID }
        refresh()
    }

    /// Regular running apps that are not in `taken` (the exclusions by default), sorted by name.
    func runningCandidates(excluding taken: [String]? = nil) -> [(name: String, id: String)] {
        let excluded = Set(taken ?? settings.excludedApps)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, id: String)? in
                guard let id = app.bundleIdentifier, !excluded.contains(id), seen.insert(id).inserted else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func chooseApp() {
        if let id = pickApp(message: "Choose an app to exclude") { addExclusion(id) }
    }

    func chooseAppForEffect() {
        if let id = pickApp(message: "Choose an app with its own close effect") { addAppEffect(id) }
    }

    func addAppEffect(_ bundleID: String) {
        guard settings.appCloseEffects[bundleID] == nil else { return }
        settings.appCloseEffects[bundleID] = settings.closeEffect.rawValue
        closeEffectChanged()
        refresh()
    }

    func setAppEffect(_ bundleID: String, _ raw: String) {
        settings.appCloseEffects[bundleID] = raw
        closeEffectChanged()
        refresh()
    }

    func removeAppEffect(_ bundleID: String) {
        settings.appCloseEffects[bundleID] = nil
        refresh()
    }

    private func pickApp(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
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
                Toggle("Glide and Bounce on Flick",
                       isOn: model.binding({ settings.glideOnFlick }, { settings.glideOnFlick = $0 }))
                Toggle("3D Tilt while Dragging",
                       isOn: model.binding({ settings.tiltOnDrag }, { settings.tiltOnDrag = $0 }))
                Toggle("Glow on Focus",
                       isOn: model.binding({ settings.focusPulse }, { settings.focusPulse = $0 }))
                Toggle("Ripple on Drop",
                       isOn: model.binding({ settings.rippleOnDrop }, { settings.rippleOnDrop = $0 }))
            }

            Section("Window Effects") {
                Picker("Close", selection: model.binding({ settings.closeEffect.rawValue }, { model.selectCloseEffect($0) })) {
                    Text("Off").tag(CloseEffectChoice.off.rawValue)
                    Text("Random").tag(CloseEffectChoice.random.rawValue)
                    Divider()
                    ForEach(CloseEffect.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Open", selection: model.binding({ settings.openEffect.rawValue }, { model.selectOpenEffect($0) })) {
                    Text("Off").tag(OpenEffectChoice.off.rawValue)
                    Text("Random").tag(OpenEffectChoice.random.rawValue)
                    Divider()
                    ForEach(WobbleEntrance.allCases, id: \.rawValue) {
                        Text($0.title).tag(OpenEffectChoice.wobble($0).rawValue)
                    }
                }
                Picker("Minimize", selection: model.binding({ settings.minimizeEffect.rawValue }, { model.selectMinimizeEffect($0) })) {
                    Text("Off").tag(MinimizeEffectChoice.off.rawValue)
                    Text("Random").tag(MinimizeEffectChoice.random.rawValue)
                    Divider()
                    ForEach(DockMorphStyle.allCases, id: \.rawValue) {
                        Text($0.title).tag(MinimizeEffectChoice.morph($0).rawValue)
                    }
                }
                Text("Open and Minimize use the jelly model: the window stays visible while it arrives, so there is no flash. Minimize morphs the window into its Dock icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SliderRow(title: "Duration",
                          value: model.binding({ settings.closeDuration }, { settings.closeDuration = $0 }),
                          range: Settings.closeSpeedRange, decimals: 2)
            }

            Section {
                if settings.appCloseEffects.isEmpty {
                    Text("No per-app effects").foregroundStyle(.secondary)
                }
                ForEach(settings.appCloseEffects.keys.sorted(), id: \.self) { id in
                    AppRow(bundleID: id, remove: { model.removeAppEffect(id) }) {
                        Picker("Close effect", selection: model.binding({ settings.appCloseEffects[id] ?? "" }, { model.setAppEffect(id, $0) })) {
                            Text("Off").tag(CloseEffectChoice.off.rawValue)
                            Text("Random").tag(CloseEffectChoice.random.rawValue)
                            Divider()
                            ForEach(CloseEffect.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(model.runningCandidates(excluding: Array(settings.appCloseEffects.keys)), id: \.id) { candidate in
                            Button(candidate.name) { model.addAppEffect(candidate.id) }
                        }
                    }
                    Button("Choose App…") { model.chooseAppForEffect() }
                }
            } header: {
                Text("Per-App Close Effects")
            } footer: {
                Text("These apps use their own close effect instead of the one above.")
            }

            Section {
                if settings.excludedApps.isEmpty {
                    Text("No excluded apps").foregroundStyle(.secondary)
                }
                ForEach(settings.excludedApps, id: \.self) { id in
                    AppRow(bundleID: id, remove: { model.removeExclusion(id) }) { EmptyView() }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(model.runningCandidates(), id: \.id) { candidate in
                            Button(candidate.name) { model.addExclusion(candidate.id) }
                        }
                    }
                    Button("Choose App…") { model.chooseApp() }
                }
            } header: {
                Text("Exclusions")
            } footer: {
                Text("Windows of these apps get no wobble, resize, maximize or close effect. Kinetiq's own windows (this one) are excluded by default.")
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
        .frame(minWidth: 440, idealWidth: 440, minHeight: 480, idealHeight: 760)
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

private struct AppRow<Accessory: View>: View {
    let bundleID: String
    let remove: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    init(bundleID: String, remove: @escaping () -> Void, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.bundleID = bundleID
        self.remove = remove
        self.accessory = accessory
    }

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    var body: some View {
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove from exclusions")
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
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 440, height: 760))
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
