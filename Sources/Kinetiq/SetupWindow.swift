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
    private let startChaos: () -> Void
    private let enabledChanged: () -> Void
    let runtimeStatus: () -> ManagementRuntimeStatus
    let systemSaver: SystemScreenSaver?
    @Published var requestedPage: ManagementPage?
    @Published var requestedLibraryEffect: String?
    @Published private(set) var effectError: String?
    private(set) var visibleWindows: [ManagedWindow] = []

    init(settings: Settings, closeEffectChanged: @escaping () -> Void, startChaos: @escaping () -> Void,
         enabledChanged: @escaping () -> Void, runtimeStatus: @escaping () -> ManagementRuntimeStatus,
         systemSaver: SystemScreenSaver? = nil) {
        self.settings = settings
        self.closeEffectChanged = closeEffectChanged
        self.startChaos = startChaos
        self.enabledChanged = enabledChanged
        self.runtimeStatus = runtimeStatus
        self.systemSaver = systemSaver
    }

    func refresh() {
        objectWillChange.send()
    }

    /// Window enumeration is explicit, never performed for every physics slider tick.
    func refreshWindows() {
        objectWillChange.send()
        visibleWindows = ManagedWindow.onScreen()
    }

    func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        enabledChanged()
        refresh()
    }

    func startScreenSaver() { startChaos() }

    /// Lets views outside this model tell the engine that a trigger owner changed.
    func closeEffectChangedPublic() {
        closeEffectChanged()
        refresh()
    }

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
        guard releaseCatalogTrigger(.close) else { return }
        settings.closeEffect = CloseEffectChoice(rawValue: raw)
        closeEffectChanged()
        refresh()
    }

    func selectOpenEffect(_ raw: String) {
        guard releaseCatalogTrigger(.open) else { return }
        settings.openEffect = OpenEffectChoice(rawValue: raw)
        closeEffectChanged()
        refresh()
    }

    func selectMinimizeEffect(_ raw: String) {
        guard releaseCatalogTrigger(.minimize) else { return }
        settings.minimizeEffect = MinimizeEffectChoice(rawValue: raw)
        DockGenie.sync(enabled: settings.minimizeEffect != .off)
        closeEffectChanged()
        refresh()
    }

    /// Original engines keep their existing keys and native trigger lifecycle.
    func applyOriginalEffect(_ effect: LibraryEffect, trigger: EffectTrigger) {
        do {
            try OriginalEffectAssignment.apply(effect, trigger: trigger, settings: settings, store: .shared)
            if trigger == .minimize { DockGenie.sync(enabled: settings.minimizeEffect != .off) }
            effectError = nil
            closeEffectChanged()
            refresh()
        } catch { effectError = error.localizedDescription }
    }

    // MARK: - Trigger assignments (shared by the library, the menu bar and the Studio)

    func assignment(for trigger: EffectTrigger) -> TriggerAssignment {
        TriggerAssignment.current(trigger, settings: settings, store: .shared)
    }

    func isAssigned(_ effect: LibraryEffect, to trigger: EffectTrigger) -> Bool {
        assignment(for: trigger) == .effect(effect)
    }

    /// Makes `effect` what `trigger` plays. Studio presets keep their saved parameters and tracks;
    /// originals write their existing preference. Returns false and sets `effectError` on failure.
    @discardableResult
    func assign(_ effect: LibraryEffect, to trigger: EffectTrigger) -> Bool {
        do {
            if case .catalog(let id) = effect {
                var preset = CatalogStore.shared.preset(id)
                guard EffectCatalog.descriptor(id).triggers.contains(trigger) else {
                    throw StudioUIError.message("\(effect.title) cannot be used for \(trigger.shortTitle).")
                }
                preset.trigger = trigger
                try CatalogStore.shared.save(preset)
            } else {
                try OriginalEffectAssignment.apply(effect, trigger: trigger, settings: settings, store: .shared)
            }
            afterAssignmentChange(trigger)
            return true
        } catch { effectError = error.localizedDescription; return false }
    }

    /// Makes a saved Studio composition what `trigger` plays (Open, Close or Minimize).
    @discardableResult
    func assignCustom(_ id: UUID, to trigger: EffectTrigger) -> Bool {
        do {
            guard CustomEffect.assignableTriggers.contains(trigger), var custom = CatalogStore.shared.customEffect(id) else {
                throw StudioUIError.message("My Effects can be used when a window opens, closes or is minimized.")
            }
            custom.trigger = trigger
            try CatalogStore.shared.saveCustom(custom)
            afterAssignmentChange(trigger)
            return true
        } catch { effectError = error.localizedDescription; return false }
    }

    /// Releases a Studio preset or My Effect from `trigger`; the built-in choice underneath plays again.
    @discardableResult
    func releaseTrigger(_ trigger: EffectTrigger) -> Bool {
        guard releaseCatalogTrigger(trigger) else { return false }
        afterAssignmentChange(trigger)
        return true
    }

    /// Off or Random for a trigger; releases any Studio owner first.
    @discardableResult
    func setTrigger(_ trigger: EffectTrigger, random: Bool) -> Bool {
        guard releaseCatalogTrigger(trigger) else { return false }
        switch trigger {
        case .close: settings.closeEffect = random ? .random : .off
        case .open: settings.openEffect = random ? .random : .off
        case .minimize: settings.minimizeEffect = random ? .random : .off
        case .drag, .overview, .manual: break
        }
        afterAssignmentChange(trigger)
        return true
    }

    private func afterAssignmentChange(_ trigger: EffectTrigger) {
        if trigger == .minimize { DockGenie.sync(enabled: settings.minimizeEffect != .off) }
        effectError = nil
        closeEffectChanged()
        refresh()
    }

    private func releaseCatalogTrigger(_ trigger: EffectTrigger) -> Bool {
        do { try CatalogStore.shared.releaseAssignment(to: trigger); effectError = nil; return true }
        catch { effectError = error.localizedDescription; return false }
    }

    func resetToDefaults() {
        if let systemSaver {
            Task {
                await systemSaver.setEnabled(false)
                guard !systemSaver.hasSelection, systemSaver.errorMessage == nil else { return }
                resetEffects()
            }
        } else {
            resetEffects()
        }
    }

    private func resetEffects() {
        settings.resetToDefaults()
        CatalogRuntime.shared.stop()
        CatalogStore.shared.resetAll()
        RenderQualityManager.shared.reset()
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

/// Existing settings, grouped by the management sidebar rather than one long form.
struct SetupControlsView: View {
    @ObservedObject var model: SetupModel
    let page: ManagementPage
    @State private var confirmingReset = false

    var body: some View {
        Form {
            switch page {
            case .physics: physics
            case .effects: effects
            case .screenSaver: screenSaver
            case .rules: rules
            case .settings: general
            default: EmptyView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Reset effect settings?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { model.resetToDefaults() }
        } message: {
            Text("Custom physics values, per-app effects and exclusions will be replaced by the defaults. This cannot be undone.")
        }
    }

    private var physics: some View {
        let settings = model.settings
        return Section("Wobble") {
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
    }

    private var effects: some View {
        let settings = model.settings
        return Section("Window Effects") {
                Picker("Close", selection: model.binding({ settings.closeEffect.rawValue }, { model.selectCloseEffect($0) })) {
                    Text("Off").tag(CloseEffectChoice.off.rawValue)
                    Text("Random").tag(CloseEffectChoice.random.rawValue)
                    Text("Liquid").tag(CloseEffectChoice.liquid.rawValue)
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
                    Text("Liquid").tag(MinimizeEffectChoice.liquid.rawValue)
                    Divider()
                    ForEach(DockMorphStyle.allCases, id: \.rawValue) {
                        Text($0.title).tag(MinimizeEffectChoice.morph($0).rawValue)
                    }
                }
                Text("Liquid melts from the top-right, spills over window edges and pools behind the Dock before slowly fading. Other minimize effects morph into the Dock icon. Minimize effects apply to the yellow button only; ⌘M remains native.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SliderRow(title: "Duration",
                          value: model.binding({ settings.closeDuration }, { settings.closeDuration = $0 }),
                          range: Settings.closeSpeedRange, decimals: 2)
        }
    }

    private var screenSaver: some View {
        let settings = model.settings
        return Section {
                if let systemSaver = model.systemSaver {
                    SystemSaverControls(manager: systemSaver, settings: settings)
                } else {
                    Text("Use the packaged Kinetiq app to configure the macOS screen saver.").foregroundStyle(.secondary)
                }
                SliderRow(title: "Event every (ms)",
                          value: model.binding({ settings.chaosEventInterval }, { settings.chaosEventInterval = $0.rounded() }),
                          range: ChaosSettings.intervalRange, decimals: 0)
                SliderRow(title: "Pieces vanish after (s)",
                          value: model.binding({ settings.chaosLifetime }, { settings.chaosLifetime = $0.rounded() }),
                          range: ChaosSettings.lifetimeRange, decimals: 0)
                SliderRow(title: "Speed",
                          value: model.binding({ settings.chaosSpeed }, { settings.chaosSpeed = $0 }),
                          range: ChaosSettings.speedRange, decimals: 2)
                SliderRow(title: "Intensity",
                          value: model.binding({ settings.chaosIntensity }, { settings.chaosIntensity = $0 }),
                          range: ChaosSettings.intensityRange, decimals: 1)
                Button("Preview Now") { model.startScreenSaver() }
                    .disabled(!Permissions.screenCaptureGranted)
                if !Permissions.screenCaptureGranted {
                    Text("Grant Screen Recording in Settings before starting the screen saver.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Screen Saver")
            } footer: {
                Text("Enable to install and select Kinetiq as the default macOS screen saver on every display and Space. macOS controls inactivity, dismissal and password requirements. Preview Now runs an in-app preview only.")
        }
    }

    private var rules: some View {
        let settings = model.settings
        return Group {
            Section {
                if settings.appCloseEffects.isEmpty {
                    Text("No per-app effects").foregroundStyle(.secondary)
                }
                ForEach(settings.appCloseEffects.keys.sorted(), id: \.self) { id in
                    AppRow(bundleID: id, remove: { model.removeAppEffect(id) }) {
                        Picker("Close effect", selection: model.binding({ settings.appCloseEffects[id] ?? "" }, { model.setAppEffect(id, $0) })) {
                            Text("Off").tag(CloseEffectChoice.off.rawValue)
                            Text("Random").tag(CloseEffectChoice.random.rawValue)
                            Text("Liquid").tag(CloseEffectChoice.liquid.rawValue)
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
                Text("These apps override the global close effect selected in Effects.")
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
        }
    }

    private var general: some View {
        let settings = model.settings
        return Group {
            Section("General") {
                Toggle("Enable Kinetiq", isOn: model.binding({ settings.enabled }, { model.setEnabled($0) }))
                Toggle("Drag from Title Bar", isOn: model.binding({ settings.titleBarDrag }, { settings.titleBarDrag = $0 }))
                Picker("Shortcut (Anywhere)", selection: model.binding({ settings.modifier }, { settings.modifier = $0 })) {
                    ForEach(DragModifier.allCases, id: \.self) { Text($0.title).tag($0) }
                }
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
                Button("Reset Effect Settings…", role: .destructive) { confirmingReset = true }
                Text("Restores physics, effects, screen saver and app rules. Your enable state and drag shortcut are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                .help("Remove app rule")
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
    let model: SetupModel
    private var window: NSWindow?

    init(settings: Settings, closeEffectChanged: @escaping () -> Void, startChaos: @escaping () -> Void,
         enabledChanged: @escaping () -> Void, runtimeStatus: @escaping () -> ManagementRuntimeStatus,
         systemSaver: SystemScreenSaver? = nil) {
        model = SetupModel(settings: settings, closeEffectChanged: closeEffectChanged, startChaos: startChaos,
                           enabledChanged: enabledChanged, runtimeStatus: runtimeStatus, systemSaver: systemSaver)
    }

    func show(page: ManagementPage? = nil, effect: LibraryEffect? = nil) {
        if window == nil {
            let hosting = NSHostingController(rootView: SetupView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Kinetiq"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1180, height: 780))
            window.contentMinSize = NSSize(width: 960, height: 700)
            window.setFrameAutosaveName("KinetiqManagement")
            window.center()
            self.window = window
        }
        model.refreshWindows()
        if let page { model.requestedPage = page }
        if let effect {
            model.requestedPage = .effects
            model.requestedLibraryEffect = effect.id
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
