// swift-tools-version: 5.9
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription
import Foundation

// Local SwiftPM paths are not pinned by Package.resolved. Verify before evaluating any target.
let hostRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let telemetryCheckout = hostRoot.appendingPathComponent("../TelemetrySDK").standardizedFileURL
let telemetryPin = try String(contentsOf: hostRoot.appendingPathComponent("Documentation/telemetry-sdk-revision.txt"),
                              encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

func telemetryGit(_ arguments: [String]) throws -> (Int32, String) {
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    command.arguments = ["-C", telemetryCheckout.path] + arguments
    command.environment = ["GIT_OPTIONAL_LOCKS": "0"]
    let output = Pipe()
    command.standardOutput = output
    command.standardError = Pipe() // Never print source diffs or local configuration.
    try command.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
    command.waitUntilExit()
    return (command.terminationStatus,
            String(data: data, encoding: .utf8) ?? "")
}

do {
    let (revisionStatus, revision) = try telemetryGit(["rev-parse", "HEAD"])
    let (cleanStatus, _) = try telemetryGit(["diff", "--quiet", "HEAD", "--"])
        let (untrackedStatus, untracked) = try telemetryGit(["ls-files", "--others", "--exclude-standard"])
    guard telemetryPin.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
            revisionStatus == 0, cleanStatus == 0, untrackedStatus == 0, untracked.isEmpty,
          revision.trimmingCharacters(in: .whitespacesAndNewlines) == telemetryPin else {
        fatalError("TelemetrySDK pin or tracked checkout is not approved.")
    }
} catch {
    fatalError("TelemetrySDK pin verification failed; provision the reviewed sibling checkout.")
}

let package = Package(
    name: "Kinetiq",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KinetiqScreenSaver", type: .dynamic, targets: ["KinetiqScreenSaver"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AerialScreensaver/PaperSaver.git", exact: "0.4.3"),
        .package(path: "../TelemetrySDK"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.6.0"),
    ],
    targets: [
        .target(name: "KinetiqCore"),
        .target(name: "KinetiqSaverSupport", dependencies: ["KinetiqCore"]),
        .target(name: "KinetiqScreenSaver", dependencies: ["KinetiqSaverSupport", "KinetiqCore"]),
        // Window-close effects: Metal shaders ported from Burn-My-Windows.
        .target(name: "KinetiqEffects", dependencies: ["KinetiqCore"], resources: [.copy("Resources")]),
        // Renders the effects headlessly: `swift run kinetiq-effects-preview --check`.
        .executableTarget(name: "kinetiq-effects-preview", dependencies: ["KinetiqEffects"], path: "Sources/KinetiqEffectsPreview"),
        .executableTarget(name: "Kinetiq", dependencies: ["KinetiqCore", "KinetiqEffects", "KinetiqSaverSupport",
                                .product(name: "PaperSaverKit", package: "PaperSaver"),
                                .product(name: "Invernomut0Telemetry", package: "TelemetrySDK"),
                                  .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                                  .product(name: "FirebaseAnalyticsCore", package: "firebase-ios-sdk")],
                              linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]),
        .testTarget(name: "KinetiqCoreTests", dependencies: ["KinetiqCore"]),
        .testTarget(name: "KinetiqEffectsTests", dependencies: ["KinetiqEffects"]),
        .testTarget(name: "KinetiqTests", dependencies: ["Kinetiq", "KinetiqScreenSaver"]),
    ]
)
