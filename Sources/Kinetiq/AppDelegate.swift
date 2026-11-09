// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import KinetiqCore
import KinetiqEffects

enum Permissions {
    static func accessibilityGranted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    static var screenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private var controller: KinetiqController?
    private var tap: EventTap?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var setupWindow: SetupWindowController?
    private var chaosSaver: ChaosSaver?
    private var systemScreenSaver: SystemScreenSaver?
    private var overviewHotKey: GlobalHotKey?
    private let telemetry = KinetiqTelemetry.forApplication()
    private var quitting = false
    private var repliedToQuit = false
    private var productCleanedUp = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await telemetry.initialize()
            guard !quitting else { return }
            ensureSetupController().requestAnalyticsConsentIfNeeded()
        }
        controller = KinetiqController(settings: settings)
        let saver = ChaosSaver(settings: settings)
        saver.observeSleep()
        chaosSaver = saver
        let systemSaver = SystemScreenSaver(settings: settings)
        systemSaver.startWatching()
        systemScreenSaver = systemSaver
        if ProcessInfo.processInfo.environment["KINETIQ_CHAOS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.quitting else { return }
                saver.start()
            }
        }
        DockGenie.sync(enabled: settings.minimizeEffect != .off)
        setUpStatusItem()
        syncOverviewShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        installSignalHandlers()
        showSetup()

        guard controller != nil else {
            NSLog("Kinetiq: Metal unavailable")
            return
        }
        if !Permissions.screenCaptureGranted { CGRequestScreenCaptureAccess() }
        // Shader compilation needs no permission: start it now so the first close doesn't wait for the compiler.
        controller?.closeEffectChanged()
        if !startTap(prompt: true) {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.startTap(prompt: false) else { return }
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUpProduct()
    }

    /// Restore windows before waiting for telemetry; never block the main run loop or quit forever.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        cleanUpProduct()
        Task { [self] in
            await telemetry.shutdown()
            replyToQuit(sender)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            replyToQuit(sender)
        }
        return .terminateLater
    }

    private func replyToQuit(_ sender: NSApplication) {
        guard !repliedToQuit else { return }
        repliedToQuit = true
        sender.reply(toApplicationShouldTerminate: true)
    }

    private func cleanUpProduct() {
        guard !productCleanedUp else { return }
        productCleanedUp = true
        permissionTimer?.invalidate()
        permissionTimer = nil
        controller?.cancelAll()
        tap?.stop()
        chaosSaver?.stop()
        systemScreenSaver?.stopWatching()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return true
    }

    @discardableResult
    private func startTap(prompt: Bool) -> Bool {
        guard !quitting, Permissions.accessibilityGranted(prompt: prompt), let controller else { return false }
        let tap = EventTap { type, event in controller.handle(type, event) }
        tap.onDisabled = { controller.cancelAll() }
        guard tap.start() else { return false }
        self.tap = tap
        controller.warmUp()
        return true
    }

    /// If we get killed with SIGTERM/SIGINT mid-animation, the real window must not stay parked.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Kinetiq")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Organized by what the user does: one submenu per window event, each showing its
    /// current choice in the title. Selecting an item applies it immediately.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Kinetiq Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = settings.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        for trigger in [EffectTrigger.drag, .open, .close, .minimize] {
            let assignment = TriggerAssignment.current(trigger, settings: settings, store: .shared)
            let item = NSMenuItem(title: "\(trigger.shortTitle): \(assignment.title)", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: trigger.symbol, accessibilityDescription: nil)
            item.submenu = triggerMenu(trigger, assignment: assignment)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let tryItem = NSMenuItem(title: "Try an Effect on the Front Window", action: nil, keyEquivalent: "")
        tryItem.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
        tryItem.submenu = tryMenu()
        menu.addItem(tryItem)
        let stop = NSMenuItem(title: "Stop & Restore Windows", action: #selector(stopCatalog), keyEquivalent: "")
        stop.isEnabled = CatalogRuntime.shared.isPlaying || controller != nil
        menu.addItem(stop)

        let arrange = NSMenuItem(title: "Arrange Windows (\(EffectCatalog.descriptor(settings.overviewLayout).title))"
                                 + (settings.overviewShortcut ? "  \(GlobalHotKey.overviewTitle)" : ""),
                                 action: #selector(showOverview), keyEquivalent: "")
        arrange.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        menu.addItem(arrange)

        menu.addItem(.separator())
        let quality = NSMenuItem(title: "Render Quality: \(RenderQualityManager.shared.title)", action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu()
        for choice in RenderQuality.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(selectQuality(_:)), keyEquivalent: "")
            item.representedObject = choice.rawValue
            item.state = RenderQualityManager.shared.selection == choice ? .on : .off
            item.target = self
            qualityMenu.addItem(item)
        }
        quality.submenu = qualityMenu
        menu.addItem(quality)

        if controller == nil {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Metal Unavailable", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Effects Library…", action: #selector(showEffects), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "Animation Studio…", action: #selector(showStudio), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSetup), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Kinetiq", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) && item.target == nil {
            item.target = self
        }
    }

    /// Encodes an effect/trigger pair for `assignEffect(_:)`; `TriggerMenuAction.parse` reads it back.
    static func menuToken(_ effect: LibraryEffect, _ trigger: EffectTrigger) -> String { "\(effect.id)|\(trigger.rawValue)" }

    private func triggerMenu(_ trigger: EffectTrigger, assignment: TriggerAssignment) -> NSMenu {
        let menu = NSMenu()
        if trigger == .drag {
            let header = NSMenuItem(title: "Wobble preset", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for preset in WobblePreset.allCases where preset != .custom || settings.preset == .custom {
                let item = NSMenuItem(title: preset.title, action: #selector(selectWobblePreset(_:)), keyEquivalent: "")
                item.representedObject = preset.rawValue
                item.state = settings.preset == preset ? .on : .off
                item.target = self
                item.indentationLevel = 1
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let studioHeader = NSMenuItem(title: "Drag behavior", action: nil, keyEquivalent: "")
            studioHeader.isEnabled = false
            menu.addItem(studioHeader)
            let classic = NSMenuItem(title: TriggerAssignment.classicWobble.title, action: #selector(setTriggerChoice(_:)), keyEquivalent: "")
            classic.representedObject = "off|\(trigger.rawValue)"
            classic.state = assignment == .classicWobble ? .on : .off
            classic.target = self
            classic.indentationLevel = 1
            menu.addItem(classic)
        } else {
            for (title, raw) in [("Off", "off"), ("Random", "random")] {
                let item = NSMenuItem(title: title, action: #selector(setTriggerChoice(_:)), keyEquivalent: "")
                item.representedObject = "\(raw)|\(trigger.rawValue)"
                item.state = (raw == "off" && assignment == .off) || (raw == "random" && assignment == .random) ? .on : .off
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let effects = LibraryEffect.supporting(trigger)
        let originals = effects.filter { !$0.isStudio }
        let studio = effects.filter(\.isStudio)
        for effect in originals {
            menu.addItem(effectItem(effect, trigger: trigger, assignment: assignment))
        }
        if !studio.isEmpty {
            if !originals.isEmpty { menu.addItem(.separator()) }
            let header = NSMenuItem(title: "Studio presets", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for effect in studio {
                let item = effectItem(effect, trigger: trigger, assignment: assignment)
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }
        if CustomEffect.assignableTriggers.contains(trigger) {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "My Effects", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for custom in CatalogStore.shared.customEffects {
                let item = NSMenuItem(title: custom.name, action: #selector(assignEffect(_:)), keyEquivalent: "")
                item.representedObject = "\(LibraryItem.customPrefix)\(custom.id.uuidString)|\(trigger.rawValue)"
                item.state = assignment.customID == custom.id ? .on : .off
                item.indentationLevel = 1
                item.target = self
                menu.addItem(item)
            }
            let create = NSMenuItem(title: CatalogStore.shared.customEffects.isEmpty ? "Create One in Animation Studio…" : "New in Animation Studio…",
                                    action: #selector(showStudio), keyEquivalent: "")
            create.indentationLevel = 1
            create.target = self
            menu.addItem(create)
        }
        return menu
    }

    private func effectItem(_ effect: LibraryEffect, trigger: EffectTrigger, assignment: TriggerAssignment) -> NSMenuItem {
        let item = NSMenuItem(title: effect.title, action: #selector(assignEffect(_:)), keyEquivalent: "")
        item.representedObject = Self.menuToken(effect, trigger)
        item.state = assignment == .effect(effect) ? .on : .off
        item.toolTip = effect.blurb
        item.target = self
        return item
    }

    /// Every effect, played once on the frontmost window and put back: nothing is closed or minimized.
    private func tryMenu() -> NSMenu {
        let menu = NSMenu()
        func header(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            items.forEach(sub.addItem)
            item.submenu = sub
            menu.addItem(item)
        }
        func builtinItem(_ effect: LibraryEffect) -> NSMenuItem {
            let item = NSMenuItem(title: effect.title, action: #selector(runBuiltinEffect(_:)), keyEquivalent: "")
            item.representedObject = effect.id
            item.toolTip = effect.blurb
            item.target = self
            return item
        }
        if !CatalogStore.shared.customEffects.isEmpty {
            header("My Effects")
            for custom in CatalogStore.shared.customEffects {
                let item = NSMenuItem(title: custom.name, action: #selector(runCustomEffect(_:)), keyEquivalent: "")
                item.representedObject = custom.id.uuidString
                item.indentationLevel = 1
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        header("Built-in effects")
        submenu("Close Effects", CloseEffect.allCases.map { builtinItem(.close($0)) })
        submenu("Entrances", WobbleEntrance.allCases.map { builtinItem(.entrance($0)) })
        submenu("Minimize Morphs", DockMorphStyle.allCases.map { builtinItem(.minimize($0)) })
        let liquid = NSMenuItem(title: LibraryEffect.liquid.title, action: #selector(runLiquid), keyEquivalent: "")
        liquid.toolTip = LibraryEffect.liquid.blurb
        liquid.target = self
        menu.addItem(liquid)
        let destruction = NSMenuItem(title: LibraryEffect.destruction.title, action: #selector(runDestruction), keyEquivalent: "")
        destruction.toolTip = LibraryEffect.destruction.blurb
        destruction.target = self
        menu.addItem(destruction)
        menu.addItem(.separator())
        header("Studio effects")
        for category in EffectCategory.allCases {
            let effects = EffectCatalog.effects.filter { $0.category == category }
            guard !effects.isEmpty else { continue }
            submenu(category.title, effects.map { descriptor in
                let item = NSMenuItem(title: descriptor.title, action: #selector(runCatalogEffect(_:)), keyEquivalent: "")
                item.representedObject = descriptor.id.rawValue
                item.toolTip = descriptor.summary
                item.target = self
                return item
            })
        }
        return menu
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if !settings.enabled { controller?.cancelAll() }
    }

    @objc private func selectWobblePreset(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let preset = WobblePreset(rawValue: raw), preset != .custom {
            settings.preset = preset
            setupController?.model.refresh()
        }
    }

    @objc private func runCatalogEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = EffectID(rawValue: raw) else { return }
        controller?.cancelAll()
        let preset = CatalogStore.shared.preset(id)
        Task { await CatalogRuntime.shared.play(preset) }
    }

    /// A built-in close shader, entrance or Dock morph as a one-layer document on the front window.
    @objc private func runBuiltinEffect(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let builtin = BuiltinLayer(id) else { return }
        controller?.cancelAll()
        let layer = builtin.makeLayer()
        let document = StudioDocument(name: builtin.effect.title, duration: layer.end, layers: [layer])
        Task { await CatalogRuntime.shared.playDocument(document) }
    }

    @objc private func runCustomEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw),
              let custom = CatalogStore.shared.customEffect(id) else { return }
        controller?.cancelAll()
        Task { await CatalogRuntime.shared.playDocument(custom.document) }
    }

    @objc private func runLiquid() { controller?.tryLiquid() }

    @objc private func runDestruction() { controller?.tryDestruction() }

    /// Opens the chosen window arrangement on the current Space; also bound to ⌃⌥↑.
    @objc func showOverview() {
        guard settings.enabled, !CatalogRuntime.shared.isPlaying else {
            // The same shortcut puts an open overview away.
            if CatalogRuntime.shared.isPlaying { CatalogRuntime.shared.dismissOverview() }
            return
        }
        controller?.cancelAll()
        let preset = CatalogStore.shared.preset(settings.overviewLayout)
        Task { await CatalogRuntime.shared.play(preset) }
    }

    @objc nonisolated private func preferencesChanged() {
        Task { @MainActor [weak self] in self?.syncOverviewShortcut() }
    }

    private func syncOverviewShortcut() {
        let wanted = settings.overviewShortcut
        if wanted, overviewHotKey == nil {
            overviewHotKey = GlobalHotKey(keyCode: GlobalHotKey.overviewKeyCode, modifiers: GlobalHotKey.overviewModifiers) { [weak self] in
                self?.showOverview()
            }
        } else if !wanted, let hotKey = overviewHotKey {
            hotKey.unregister()
            overviewHotKey = nil
        }
    }

    @objc private func selectQuality(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let choice = RenderQuality(rawValue: raw) {
            RenderQualityManager.shared.selection = choice
        }
    }

    /// "effectID|trigger" or "custom:<uuid>|trigger": makes it what the trigger plays, like the library does.
    @objc private func assignEffect(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String else { return }
        if token.hasPrefix(LibraryItem.customPrefix), let bar = token.lastIndex(of: "|"),
           let id = UUID(uuidString: String(token[token.index(token.startIndex, offsetBy: LibraryItem.customPrefix.count)..<bar])),
           let trigger = EffectTrigger(rawValue: String(token[token.index(after: bar)...])) {
            ensureSetupController().model.assignCustom(id, to: trigger)
            return
        }
        guard let (effect, trigger) = Self.parseToken(token) else { return }
        ensureSetupController().model.assign(effect, to: trigger)
    }

    /// "off|trigger" or "random|trigger".
    @objc private func setTriggerChoice(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String else { return }
        let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let trigger = EffectTrigger(rawValue: parts[1]) else { return }
        ensureSetupController().model.setTrigger(trigger, random: parts[0] == "random")
    }

    static func parseToken(_ token: String) -> (LibraryEffect, EffectTrigger)? {
        guard let bar = token.lastIndex(of: "|"),
              let effect = LibraryEffect.find(String(token[..<bar])),
              let trigger = EffectTrigger(rawValue: String(token[token.index(after: bar)...])) else { return nil }
        return (effect, trigger)
    }

    @objc private func stopCatalog() { controller?.cancelAll(); CatalogRuntime.shared.stop() }

    @objc private func showStudio() {
        showSetup()
        setupWindow?.show(page: .animationStudio)
    }

    @objc private func showEffects() {
        showSetup()
        setupWindow?.show(page: .effects)
    }

    @objc private func showSetup() {
        ensureSetupController().show()
    }

    private var setupController: SetupWindowController? { setupWindow }

    /// The management model also serves menu bar actions, so it exists even while its window is closed.
    @discardableResult
    private func ensureSetupController() -> SetupWindowController {
        if let setupWindow { return setupWindow }
        let controller = SetupWindowController(settings: settings, closeEffectChanged: { [weak self] in
            self?.controller?.closeEffectChanged()
        }, startChaos: { [weak self] in
            self?.chaosSaver?.start()
        }, enabledChanged: { [weak self] in
            guard let self, !self.settings.enabled else { return }
            self.controller?.cancelAll()
        }, runtimeStatus: { [weak self] in
            ManagementRuntimeStatus(metalAvailable: self?.controller != nil,
                                    eventTapRunning: self?.tap?.isRunning == true)
        }, systemSaver: systemScreenSaver, telemetry: telemetry)
        setupWindow = controller
        return controller
    }
}
