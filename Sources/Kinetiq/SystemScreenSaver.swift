// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqSaverSupport
import PaperSaverKit
import os

/// Owns installation and the macOS selection, not an independent inactivity overlay.
@MainActor
final class SystemScreenSaver: ObservableObject {
    @Published private(set) var isChanging = false
    @Published private(set) var isSelected = false
    @Published private(set) var hasSelection = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var capturedAt: Date?

    private let settings: Settings
    private let paperSaver = PaperSaver()
    private var timer: Timer?
    private var preparation: Task<Void, Never>?
    private var preparedForIdle = false
    private static let log = Logger(subsystem: "io.github.invernomut0.Kinetiq", category: "system-saver")

    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Kinetiq.saver", isDirectory: true)
    }

    private static var backupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Kinetiq/PreviousScreenSaver.plist")
    }

    init(settings: Settings) { self.settings = settings }

    func startWatching() {
        refreshStatus()
        // An older chaosEnabled preference did not mean the user selected a system module.
        if !isSelected { settings.chaosEnabled = false }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareBeforeSystemIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if isSelected, settings.chaosEnabled {
            preparation = Task { [weak self] in
                guard let self else { return }
                do {
                    try installModule()
                    try await prepareScene()
                } catch is CancellationError {
                    // A user action superseded the background preparation.
                } catch { report(error) }
                preparation = nil
            }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
        preparation?.cancel()
        preparation = nil
        // The native module and its last scene remain available when Kinetiq quits.
    }

    func refreshStatus() {
        let sections = (try? paperSaver.readStore())?.allSections ?? []
        let choices = sections.compactMap { $0.idle ?? $0.linked }
        hasSelection = choices.contains { Self.isKinetiq($0) }
        isSelected = !choices.isEmpty && choices.allSatisfy { Self.isKinetiq($0) }
        if capturedAt == nil { capturedAt = (try? SaverArchive.read())?.capturedAt }
    }

    /// Called only after explicit user consent, including consent to local desktop snapshots.
    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        errorMessage = nil
        preparation?.cancel()
        preparation = nil
        defer { isChanging = false; refreshStatus() }
        var savedScene = false
        do {
            if enabled {
                guard Permissions.screenCaptureGranted else { throw SystemSaverError.capturePermission }
                try installModule()
                try await prepareScene()
                savedScene = true
                let original = try paperSaver.readStore()
                let backup = StoreFile(url: Self.backupURL)
                // Never overwrite the pre-Kinetiq selection on an idempotent enable.
                if !original.allSections.contains(where: { Self.isKinetiq($0.idle ?? $0.linked) }) {
                    try FileManager.default.createDirectory(at: Self.backupURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    try backup.write(original)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.backupURL.path)
                    settings.chaosPreviousIdleSeconds = paperSaver.getIdleTime()
                }
                try await paperSaver.setScreensaverEverywhere(module: "Kinetiq")
                do {
                    try paperSaver.setIdleTime(seconds: settings.chaosIdleMinutes * 60)
                } catch {
                    try await restorePreviousSelection()
                    throw error
                }
                settings.chaosEnabled = true
                preparedForIdle = false
            } else {
                try await restorePreviousSelection()
                settings.chaosEnabled = false
                try removeSavedScene()
            }
        } catch {
            refreshStatus()
            if enabled, savedScene, !hasSelection { try? removeSavedScene() }
            report(error)
        }
    }

    func setIdleMinutes(_ minutes: Int) {
        let previous = settings.chaosIdleMinutes
        objectWillChange.send()
        settings.chaosIdleMinutes = minutes
        guard settings.chaosEnabled, isSelected else { return }
        do {
            try paperSaver.setIdleTime(seconds: settings.chaosIdleMinutes * 60)
            preparedForIdle = false
        } catch {
            settings.chaosIdleMinutes = previous
            report(error)
        }
    }

    func openSystemSettings() {
        let pane = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
            ? "com.apple.Wallpaper-Settings.extension" : "com.apple.ScreenSaver-Settings.extension"
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func installModule() throws {
        guard let resources = Bundle.main.resourceURL else { throw SystemSaverError.moduleMissing }
        let source = resources.appendingPathComponent("Kinetiq.saver", isDirectory: true)
        let fm = FileManager.default
        guard let sourceBundle = Bundle(url: source), sourceBundle.bundleIdentifier == "io.github.invernomut0.Kinetiq.ScreenSaver" else {
            throw SystemSaverError.moduleMissing
        }
        let destination = Self.installedURL
        if let installed = Bundle(url: destination),
              installed.bundleIdentifier == sourceBundle.bundleIdentifier,
              installed.infoDictionary?["CFBundleVersion"] as? String == sourceBundle.infoDictionary?["CFBundleVersion"] as? String,
              let installedBinary = installed.executableURL, let sourceBinary = sourceBundle.executableURL,
              fm.contentsEqual(atPath: installedBinary.path, andPath: sourceBinary.path) { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".Kinetiq-\(UUID().uuidString).saver")
        try fm.copyItem(at: source, to: staging)
        defer { try? fm.removeItem(at: staging) }
        if fm.fileExists(atPath: destination.path) {
            guard Bundle(url: destination)?.bundleIdentifier == sourceBundle.bundleIdentifier else { throw SystemSaverError.nameConflict }
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
    }

    private func prepareBeforeSystemIdle() {
        guard settings.chaosEnabled, !isChanging, preparation == nil, Permissions.screenCaptureGranted else { return }
        refreshStatus()
        guard isSelected else { return } // Never reselect after the user chose another saver in macOS.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let delay = Double(paperSaver.getIdleTime())
        if idle < max(1, delay - 20) { preparedForIdle = false }
        guard delay > 0, idle >= max(0, delay - 20), idle < delay, !preparedForIdle else { return }
        preparedForIdle = true
        preparation = Task { [weak self] in
            guard let self else { return }
            do { try await prepareScene() } catch is CancellationError {
                // Disabling or resetting cancels this preparation.
            } catch { report(error) }
            preparation = nil
        }
    }

    private func prepareScene() async throws {
        let windows = try await DesktopSnapshot.capture()
        try Task.checkCancellation()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var displays: [SaverArchive.Display] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let wallpaper = await DesktopSnapshot.wallpaper(for: screen) else { continue }
            try Task.checkCancellation()
            let frame = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            let local = try windows.filter { frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map {
                try SaverArchive.Window(frame: $0.frame.offsetBy(dx: -frame.minX, dy: -frame.minY), image: $0.image, isDock: $0.owner == "Dock")
            }
            displays.append(try SaverArchive.Display(id: id, size: screen.frame.size, wallpaper: wallpaper, windows: local))
        }
        let archive = SaverArchive(displays: displays, settings: settings.chaosSettings)
        try Task.checkCancellation()
        try archive.write()
        capturedAt = archive.capturedAt
    }

    private func restorePreviousSelection() async throws {
        let file = StoreFile()
        let current = try file.read()
        if current.allSections.contains(where: { Self.isKinetiq($0.idle ?? $0.linked) }) {
            let original = try StoreFile(url: Self.backupURL).read()
            let restored = Self.restoringScreenSaver(in: current, from: original)
            let snapshot = try file.write(restored)
            do {
                let agent = WallpaperAgent()
                try await agent.restart()
                // PaperSaver's respawn check can race an already-respawned agent. Store verification is authoritative.
                do { try await agent.waitForRespawn(timeout: .seconds(5)) } catch {
                    Self.log.warning("wallpaper agent respawn check: \(error.localizedDescription)")
                }
                let deadline = ContinuousClock.now + .seconds(4)
                var stamp = file.modificationStamp()
                var stableSince = ContinuousClock.now
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                    let next = file.modificationStamp()
                    if next != stamp { stamp = next; stableSince = .now }
                    else if ContinuousClock.now - stableSince >= .milliseconds(750) { break }
                }
                let actual = try file.read()
                guard !actual.allSections.contains(where: { Self.isKinetiq($0.idle ?? $0.linked) }),
                      Self.saverSlotsMatch(actual, restored) else { throw SystemSaverError.restoreFailed }
            } catch {
                try file.restore(snapshot)
                try await WallpaperAgent().restart()
                throw error
            }
        }
        if let previous = settings.chaosPreviousIdleSeconds,
           paperSaver.getIdleTime() == settings.chaosIdleMinutes * 60 {
            try paperSaver.setIdleTime(seconds: previous)
        }
        settings.chaosPreviousIdleSeconds = nil
        if FileManager.default.fileExists(atPath: Self.backupURL.path) { try FileManager.default.removeItem(at: Self.backupURL) }
        let backupCopy = Self.backupURL.appendingPathExtension("backup")
        if FileManager.default.fileExists(atPath: backupCopy.path) { try FileManager.default.removeItem(at: backupCopy) }
    }

    /// Restore only slots still owned by Kinetiq. Preserve newer wallpaper and other-saver choices.
    static func restoringScreenSaver(in current: WallpaperStore, from original: WallpaperStore) -> WallpaperStore {
        var result = current
        let fallback = original.slot(.screensaver)
        func restore(_ section: StoreSection?, previous: StoreSection?) -> StoreSection? {
            guard var section, isKinetiq(section.idle ?? section.linked) else { return section }
            section.idle = previous?.idle ?? previous?.linked ?? fallback
            section.linked = nil
            section.type = section.desktop == nil ? .idle : .individual
            return section
        }
        result.allSpacesAndDisplays = restore(current.allSpacesAndDisplays, previous: original.allSpacesAndDisplays)
        result.systemDefault = restore(current.systemDefault, previous: original.systemDefault)
        for (id, section) in current.displays { result.displays[id] = restore(section, previous: original.displays[id]) }
        for (spaceID, entry) in current.spaces {
            result.spaces[spaceID]?.default = restore(entry.default, previous: original.spaces[spaceID]?.default)
            for (displayID, section) in entry.displays {
                result.spaces[spaceID]?.displays[displayID] = restore(section, previous: original.spaces[spaceID]?.displays[displayID])
            }
        }
        return result
    }

    private static func isKinetiq(_ slot: SlotConfiguration?) -> Bool {
        guard case .screenSaver(let url)? = slot?.configuration else { return false }
        return url.standardizedFileURL == installedURL.standardizedFileURL
    }

    private static func saverSlotsMatch(_ actual: WallpaperStore, _ expected: WallpaperStore) -> Bool {
        func matches(_ a: StoreSection?, _ b: StoreSection?) -> Bool {
            let a = a?.idle ?? a?.linked
            let b = b?.idle ?? b?.linked
            return a?.choices == b?.choices && a?.optionValues == b?.optionValues && a?.shuffle == b?.shuffle
        }
        guard matches(actual.allSpacesAndDisplays, expected.allSpacesAndDisplays),
              matches(actual.systemDefault, expected.systemDefault) else { return false }
        for (id, section) in expected.displays where !matches(actual.displays[id], section) { return false }
        for (id, entry) in expected.spaces {
            guard matches(actual.spaces[id]?.default, entry.default) else { return false }
            for (displayID, section) in entry.displays where !matches(actual.spaces[id]?.displays[displayID], section) { return false }
        }
        return true
    }

    private func removeSavedScene() throws {
        if FileManager.default.fileExists(atPath: SaverArchive.directory.path) {
            try FileManager.default.removeItem(at: SaverArchive.directory)
        }
        capturedAt = nil
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        Self.log.error("system screen saver: \(error.localizedDescription)")
    }
}

private enum SystemSaverError: LocalizedError {
    case capturePermission, moduleMissing, nameConflict, restoreFailed

    var errorDescription: String? {
        switch self {
        case .capturePermission: return "Grant Screen Recording before enabling the system screen saver."
        case .moduleMissing: return "The native screen saver is missing. Run the packaged Kinetiq.app built with scripts/build-app.sh."
        case .nameConflict: return "A different Kinetiq.saver already exists in your Screen Savers folder. Rename it before continuing."
        case .restoreFailed: return "macOS did not keep the previous screen saver selection. Your Kinetiq selection was restored; try again or open System Settings."
        }
    }
}