// swift-tools-version: 5.9
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Kinetiq",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KinetiqScreenSaver", type: .dynamic, targets: ["KinetiqScreenSaver"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AerialScreensaver/PaperSaver.git", exact: "0.4.3"),
    ],
    targets: [
        .target(name: "KinetiqCore"),
        .target(name: "KinetiqSaverSupport", dependencies: ["KinetiqCore"]),
        .target(name: "KinetiqScreenSaver", dependencies: ["KinetiqSaverSupport", "KinetiqCore"]),
        // Window-close effects: Metal shaders ported from Burn-My-Windows.
        .target(name: "KinetiqEffects", resources: [.copy("Resources")]),
        // Renders the effects headlessly: `swift run kinetiq-effects-preview --check`.
        .executableTarget(name: "kinetiq-effects-preview", dependencies: ["KinetiqEffects"], path: "Sources/KinetiqEffectsPreview"),
        .executableTarget(name: "Kinetiq", dependencies: ["KinetiqCore", "KinetiqEffects", "KinetiqSaverSupport",
                                .product(name: "PaperSaverKit", package: "PaperSaver")]),
        .testTarget(name: "KinetiqCoreTests", dependencies: ["KinetiqCore"]),
        .testTarget(name: "KinetiqEffectsTests", dependencies: ["KinetiqEffects"]),
        .testTarget(name: "KinetiqTests", dependencies: ["Kinetiq", "KinetiqScreenSaver"]),
    ]
)
