// swift-tools-version: 5.9
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Kinetiq",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KinetiqCore"),
        // Window-close effects: Metal shaders ported from Burn-My-Windows.
        .target(name: "KinetiqEffects", resources: [.copy("Resources")]),
        // Renders the effects headlessly: `swift run kinetiq-effects-preview --check`.
        .executableTarget(name: "kinetiq-effects-preview", dependencies: ["KinetiqEffects"], path: "Sources/KinetiqEffectsPreview"),
        .executableTarget(name: "Kinetiq", dependencies: ["KinetiqCore", "KinetiqEffects"]),
        .testTarget(name: "KinetiqCoreTests", dependencies: ["KinetiqCore"]),
        .testTarget(name: "KinetiqEffectsTests", dependencies: ["KinetiqEffects"]),
    ]
)
