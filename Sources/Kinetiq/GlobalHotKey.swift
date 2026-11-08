// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation

/// One system-wide shortcut through Carbon's `RegisterEventHotKey`: macOS delivers only this
/// combination to Kinetiq, so no other keystroke is observed and no permission is needed.
@MainActor
final class GlobalHotKey {
    /// ⌃⌥↑ — Mission Control is ⌃↑; this combination is free by default.
    static let overviewKeyCode = UInt32(kVK_UpArrow)
    static let overviewModifiers = UInt32(controlKey | optionKey)
    static let overviewTitle = "⌃⌥↑"

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    private var reference: EventHotKeyRef?
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4E_5451), id: id) // "KNTQ"
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref else {
            return nil
        }
        reference = ref
        Self.handlers[id] = action
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let id = hotKey.id
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.handlers[id]?() } }
            return noErr
        }, 1, &type, nil, nil)
    }
}
