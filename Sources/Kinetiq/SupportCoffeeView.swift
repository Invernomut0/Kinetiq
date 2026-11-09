// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Native equivalent of the supplied web button; loads no scripts, fonts or payment content.
struct SupportCoffeeView: View {
    static let destination = URL(string: "https://buymeacoffee.com/invernomut0")!
    static let title = "Buy me a coffee"
    private static let yellow = Color(red: 1, green: 221.0 / 255, blue: 0)
    @State private var hovering = false

    var body: some View {
        Link(destination: Self.destination) {
            HStack(spacing: 7) {
                Text("☕").font(.system(size: 18)).accessibilityHidden(true)
                Text(Self.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(hovering ? Color(red: 1, green: 0.90, blue: 0.08) : Self.yellow,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Support Kinetiq — opens Buy Me a Coffee in your browser")
        .accessibilityLabel(Self.title)
        .accessibilityHint("Opens Invernomut0's support page in your browser")
        .accessibilityIdentifier("kinetiq.support.buyMeACoffee")
    }
}