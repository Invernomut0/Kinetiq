// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import KinetiqCore

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = KinetiqController(settings: settings)
        let saver = ChaosSaver(settings: settings)
        saver.observeSleep()
        chaosSaver = saver
        let systemSaver = SystemScreenSaver(settings: settings)
        systemSaver.startWatching()
        systemScreenSaver = systemSaver
        if ProcessInfo.processInfo.environment["KINETIQ_CHAOS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saver.start() }
        }
        DockGenie.sync(enabled: settings.minimizeEffect != .off)
        setUpStatusItem()
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
        guard Permissions.accessibilityGranted(prompt: prompt), let controller else { return false }
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

    /// Only the everyday controls live in the menu; everything else is in the detached Setup window.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Kinetiq Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = settings.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        let titleBar = NSMenuItem(title: "Drag from Title Bar", action: #selector(toggleTitleBarDrag), keyEquivalent: "")
        titleBar.state = settings.titleBarDrag ? .on : .off
        menu.addItem(titleBar)

        let modifierMenu = NSMenu()
        for modifier in DragModifier.allCases {
            let entry = NSMenuItem(title: modifier.title, action: #selector(selectModifier(_:)), keyEquivalent: "")
            entry.representedObject = modifier.rawValue
            entry.state = settings.modifier == modifier ? .on : .off
            entry.target = self
            modifierMenu.addItem(entry)
        }
        let modifierItem = NSMenuItem(title: "Shortcut (Anywhere): \(settings.modifier.title)", action: nil, keyEquivalent: "")
        modifierItem.submenu = modifierMenu
        menu.addItem(modifierItem)

        menu.addItem(.separator())
        for category in EffectCategory.allCases {
            let categoryItem = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            let categoryMenu = NSMenu()
            let effects = EffectCatalog.effects.filter { $0.category == category }
            for submenu in Array(Set(effects.map(\.submenu))).sorted() {
                let group = NSMenuItem(title: submenu, action: nil, keyEquivalent: "")
                let choices = NSMenu()
                for effect in effects.filter({ $0.submenu == submenu }) {
                    let item = NSMenuItem(title: effect.title, action: #selector(runCatalogEffect(_:)), keyEquivalent: "")
                    item.representedObject = effect.id.rawValue
                    item.target = self
                    choices.addItem(item)
                }
                group.submenu = choices
                categoryMenu.addItem(group)
            }
            categoryItem.submenu = categoryMenu
            menu.addItem(categoryItem)
        }
        let quality = NSMenuItem(title: "Render Quality", action: nil, keyEquivalent: "")
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
        menu.addItem(NSMenuItem(title: "Stop & Restore Windows", action: #selector(stopCatalog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Animation Studio…", action: #selector(showStudio), keyEquivalent: ""))

        if controller == nil {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Metal Unavailable", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Setup…", action: #selector(showSetup), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Kinetiq", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) && item.target == nil {
            item.target = self
        }
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        if !settings.enabled { controller?.cancelAll() }
    }

    @objc private func toggleTitleBarDrag() {
        settings.titleBarDrag.toggle()
    }

    @objc private func selectModifier(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let modifier = DragModifier(rawValue: raw) {
            settings.modifier = modifier
        }
    }

    @objc private func runCatalogEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = EffectID(rawValue: raw) else { return }
        controller?.cancelAll()
        let preset = CatalogStore.shared.preset(id)
        Task { await CatalogRuntime.shared.play(preset) }
    }

    @objc private func selectQuality(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let choice = RenderQuality(rawValue: raw) {
            RenderQualityManager.shared.selection = choice
        }
    }

    @objc private func stopCatalog() { controller?.cancelAll(); CatalogRuntime.shared.stop() }

    @objc private func showStudio() {
        showSetup()
        setupWindow?.show(page: .animationStudio)
    }

    @objc private func showSetup() {
        if setupWindow == nil {
            setupWindow = SetupWindowController(settings: settings, closeEffectChanged: { [weak self] in
                self?.controller?.closeEffectChanged()
            }, startChaos: { [weak self] in
                self?.chaosSaver?.start()
            }, enabledChanged: { [weak self] in
                guard let self, !self.settings.enabled else { return }
                self.controller?.cancelAll()
            }, runtimeStatus: { [weak self] in
                ManagementRuntimeStatus(metalAvailable: self?.controller != nil,
                                        eventTapRunning: self?.tap?.isRunning == true)
            }, systemSaver: systemScreenSaver)
        }
        setupWindow?.show()
    }
}
