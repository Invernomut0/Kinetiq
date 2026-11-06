// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import KinetiqCore
import Metal
import QuartzCore

/// Main-thread bridge between real Metal completion timings, ProcessInfo and UI.
/// Only selection is persisted. Thermal/Low Power safety may cap manual choices;
/// budget (not resolvedQuality's summary label) is the authoritative resource limit.
@MainActor
final class RenderQualityManager: NSObject, ObservableObject {
    static let shared = RenderQualityManager()
    static let preferenceKey = "renderQuality"

    @Published var selection: RenderQuality {
        didSet {
            defaults.set(selection.rawValue, forKey: Self.preferenceKey)
            policy.select(selection)
            refreshEnvironment()
        }
    }
    @Published private(set) var budget: RenderBudget
    @Published private(set) var resolvedQuality: RenderQuality
    @Published private(set) var gpuMilliseconds: Double?
    var reason: String { policy.reason }
    var title: String { selection == .auto ? "Auto · \(resolvedQuality.title)" : resolvedQuality.title }

    private let defaults: UserDefaults
    private var policy: RenderQualityPolicy

    /// An isolated real UserDefaults suite can be supplied by tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let selected = defaults.string(forKey: Self.preferenceKey).flatMap(RenderQuality.init(rawValue:)) ?? .auto
        selection = selected
        policy = RenderQualityPolicy(selection: selected)
        budget = policy.budget
        resolvedQuality = policy.resolvedQuality
        super.init()
        defaults.set(selected.rawValue, forKey: Self.preferenceKey)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
            name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
        refreshEnvironment()
    }

    func recordGPUTime(_ seconds: Double) {
        refreshEnvironment()
        policy.recordGPUTime(seconds, at: CACurrentMediaTime())
        publish()
    }

    @objc nonisolated private func environmentChanged() {
        Task { @MainActor [weak self] in self?.refreshEnvironment() }
    }

    func refreshEnvironment() {
        let state: RenderQualityPolicy.ThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = .nominal
        case .fair: state = .fair
        case .serious: state = .serious
        case .critical: state = .critical
        @unknown default: state = .serious
        }
        policy.refreshEnvironment(thermalState: state, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        publish()
    }

    /// Clears runtime evidence as well as restoring the default selection.
    func reset() {
        policy = RenderQualityPolicy()
        selection = .auto
    }

    private func publish() {
        if budget != policy.budget { budget = policy.budget }
        if resolvedQuality != policy.resolvedQuality { resolvedQuality = policy.resolvedQuality }
        if gpuMilliseconds != policy.gpuMilliseconds { gpuMilliseconds = policy.gpuMilliseconds }
    }

    /// Call before commit. No main-actor scene or command buffer crosses into
    /// the Task: only the measured, Sendable duration is captured. Unsupported
    /// timestamps and failed commands are ignored, never replaced with CPU time.
    nonisolated static func trackGPUCompletion(_ command: MTLCommandBuffer) {
        command.addCompletedHandler { completed in
            guard completed.status == .completed, completed.gpuStartTime > 0 else { return }
            let seconds = completed.gpuEndTime - completed.gpuStartTime
            guard seconds.isFinite, (0.00001...1).contains(seconds) else { return }
            Task { @MainActor in shared.recordGPUTime(seconds) }
        }
    }
}