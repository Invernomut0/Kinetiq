// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import simd

/// Ways a new window can arrive with the jelly model, starting from the window as it is (nothing is hidden first).
public enum WobbleEntrance: String, CaseIterable, Sendable {
    case wobblePop, ripple, stoneInWater, shockwave, jellySquash, quake

    public var title: String {
        switch self {
        case .wobblePop: return "Wobble Pop"
        case .ripple: return "Ripple"
        case .stoneInWater: return "Stone in Water"
        case .shockwave: return "Shockwave"
        case .jellySquash: return "Jelly Squash"
        case .quake: return "Quake"
        }
    }

    /// Sets `model` in motion. `drop` is where the stone falls (window-local points); the others ignore it.
    public func apply(to model: KinetiqModel, drop: SIMD2<Float>) {
        let center = model.size / 2
        switch self {
        case .wobblePop:
            model.unmaximize(intensity: 0.3)
        case .ripple:
            model.pullToRest()
            model.ripple(atLocal: center, amplitude: 9, wavelength: 170, speed: 650, duration: 1.4)
        case .stoneInWater:
            model.pullToRest()
            // A stone makes rings that start tight and fast, and a smaller one follows it.
            model.ripple(atLocal: drop, amplitude: 11, wavelength: 85, speed: 520, duration: 2.0, decay: 0.8)
            model.ripple(atLocal: drop, amplitude: 5, wavelength: 55, speed: 420, duration: 1.8, decay: 0.7, delay: 0.25)
        case .shockwave:
            model.unmaximize(intensity: 0.35)
            model.ripple(atLocal: center, amplitude: 12, wavelength: 230, speed: 950, duration: 1.2, decay: 0.35)
        case .jellySquash:
            model.squeeze(axis: 1, amount: 0.045)
        case .quake:
            model.shear(amount: 0.02)
        }
    }
}
