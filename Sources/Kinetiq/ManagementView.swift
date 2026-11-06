// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KinetiqCore
import SwiftUI

/// Only destinations backed by real engine capabilities appear in the sidebar.
enum ManagementPage: String, CaseIterable, Identifiable {
    case overview, windows, effects, animationStudio, physics, layouts, workspaces, rules, performance, diagnostics, settings, screenSaver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .windows: return "Windows"
        case .effects: return "Effects"
        case .animationStudio: return "Animation Studio"
        case .physics: return "Physics"
        case .layouts: return "Layouts"
        case .workspaces: return "Workspaces"
        case .screenSaver: return "Screen Saver"
        case .rules: return "Rules"
        case .performance: return "Performance"
        case .diagnostics: return "Diagnostics"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .windows: return "macwindow.on.rectangle"
        case .effects: return "sparkles"
        case .animationStudio: return "timeline.selection"
        case .physics: return "atom"
        case .layouts: return "rectangle.3.group"
        case .workspaces: return "cube"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .screenSaver: return "display"
        case .rules: return "line.3.horizontal.decrease.circle"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Your desktop, with a little more life."
        case .windows: return "A read-only snapshot of visible desktop windows."
        case .effects: return "Give every arrival, exit and minimize its own character."
        case .animationStudio: return "Compose captured-window motion with layers, tracks and keyframes."
        case .physics: return "Tune the spring model behind every movement."
        case .layouts: return "Arrange captured windows with Orbit and Exposé 3D."
        case .workspaces: return "Current Space only, no native Space switching."
        case .performance: return "Actual GPU completion timings and active resource budgets."
        case .screenSaver: return "Let your desktop fall apart. Bring it back with a gesture."
        case .rules: return "Choose which apps join in, and which stay untouched."
        case .diagnostics: return "Live system checks. No simulated telemetry."
        case .settings: return "General controls, permissions and a fresh start."
        }
    }
}

/// The delegate supplies process state; permissions alone do not imply a running engine.
struct ManagementRuntimeStatus {
    let metalAvailable: Bool
    let eventTapRunning: Bool
}

/// Public Core Graphics metadata only: inspecting this page never moves or captures a window.
struct ManagedWindow: Identifiable {
    let id: CGWindowID
    let owner: String
    let title: String
    let width: Int
    let height: Int

    static func onScreen() -> [ManagedWindow] {
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = entry[kCGWindowNumber as String] as? UInt32,
                  let owner = entry[kCGWindowOwnerName as String] as? String,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"], width > 1, height > 1 else { return nil }
            let title = entry[kCGWindowName as String] as? String ?? ""
            return ManagedWindow(id: id, owner: owner, title: title, width: Int(width), height: Int(height))
        }
    }
}

/// Native management shell: navigation never starts or stops the effects engine.
struct SetupView: View {
    @ObservedObject var model: SetupModel
    @State private var selection: ManagementPage? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var libraryCategory: EffectCategory? = nil

    private var page: ManagementPage { selection ?? .overview }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(ManagementPage.allCases) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.vertical, 5)
                            .tag(destination)
                    }
                }
                .listStyle(.sidebar)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "water.waves").foregroundStyle(Color.accentColor)
                        Text("KINETIQ").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.8)
                        Spacer()
                    }
                    Text("Made to move.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                if [.overview, .windows, .diagnostics].contains(page) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            switch page {
                            case .overview: overview
                            case .windows: windows
                            default: diagnostics
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(32)
                    }
                } else if page == .effects {
                    EffectsLibraryView(model: model, initialCategory: libraryCategory)
                } else if page == .animationStudio {
                    AnimationStudioView()
                } else if page == .performance {
                    PerformanceView()
                } else if page == .layouts || page == .workspaces {
                    CatalogArrangementView(workspaces: page == .workspaces)
                } else if page == .physics {
                    VStack(alignment: .leading, spacing: 0) {
                        Button("Explore Physics in Effects Library", systemImage: "atom") {
                            libraryCategory = .physics
                            selection = .effects
                        }
                        .padding(.horizontal, 32).padding(.top, 12)
                        SetupControlsView(model: model, page: page)
                    }
                } else {
                    SetupControlsView(model: model, page: page).id(page)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Kinetiq — \(page.title)")
        }
        .tint(.blue)
        .onReceive(model.$requestedPage) { requested in
            if let requested { selection = requested }
        }
        .frame(minWidth: 960, minHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshWindows() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in model.refreshWindows() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in model.refreshWindows() }
        .onChange(of: selection) { _, page in
            if page == .windows { model.refreshWindows() } else { model.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Show or hide sidebar")
                .accessibilityLabel("Toggle sidebar")
                Text(page.title).font(.title2.bold())
                Spacer()
                Button { model.refreshWindows() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh permissions, engine status and windows")
                    .accessibilityLabel("Refresh status")
            }
            Text(page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var overview: some View {
        let runtime = model.runtimeStatus()
        let accessibility = Permissions.accessibilityGranted(prompt: false)
        let recording = Permissions.screenCaptureGranted
        return VStack(alignment: .leading, spacing: 28) {
            Text(version).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                StatusCard(title: "Engine", symbol: "power", value: engineTitle(runtime),
                           healthy: model.settings.enabled && runtime.metalAvailable && runtime.eventTapRunning && accessibility && recording)
                StatusCard(title: "Accessibility", symbol: "figure.stand", value: accessibility ? "Granted" : "Not granted", healthy: accessibility)
                StatusCard(title: "Screen Recording", symbol: "lock.rectangle", value: recording ? "Granted" : "Not granted", healthy: recording)
            }

            ManagementCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A little motion. A different desktop.").font(.system(size: 21, weight: .semibold))
                            Text("Wobbly windows, GPU-powered effects and playful desktop physics — all controlled from one place.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "water.waves")
                            .font(.system(size: 38, weight: .light)).foregroundStyle(.blue)
                            .accessibilityHidden(true)
                    }
                    Divider()
                    HStack {
                        Label(model.settings.enabled ? "Effects enabled" : "Effects paused", systemImage: model.settings.enabled ? "play.circle" : "pause.circle")
                        Spacer()
                        Toggle("Enable effects", isOn: model.binding({ model.settings.enabled }, { model.setEnabled($0) }))
                            .labelsHidden().toggleStyle(.switch)
                            .help("Pausing restores windows involved in active effects")
                    }
                    HStack(spacing: 12) {
                        Button("Explore Effects") { selection = .effects }.buttonStyle(.borderedProminent)
                        Button("Tune Physics") { selection = .physics }.buttonStyle(.bordered)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Make room for motion").font(.headline)
                Text("Accessibility lets Kinetiq follow gestures and move windows. Screen Recording lets Metal animate a captured window. Without both permissions, effects may be unavailable.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                permissionButtons
                Text("After changing access in System Settings, refresh permissions. macOS may require an app restart. Closing this window does not stop Kinetiq.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("Native windows are restored after every animation.", systemImage: "checkmark.shield")
                Label("App exclusions and per-app effects stay under your control.", systemImage: "macwindow.on.rectangle")
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var permissionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack { permissionActions }
            VStack(alignment: .leading) { permissionActions }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var permissionActions: some View {
        Button("Request Accessibility") { Permissions.openPrivacySettings("Privacy_Accessibility") }
        Button("Request Screen Recording") {
            CGRequestScreenCaptureAccess()
            Permissions.openPrivacySettings("Privacy_ScreenCapture")
            model.refresh()
        }
        Button("Refresh Permissions") { model.refresh() }
    }

    private var windows: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(model.visibleWindows.count) visible windows").font(.headline)
                Spacer()
                Button("Refresh Windows") { model.refreshWindows() }.buttonStyle(.bordered)
            }
            if !Permissions.screenCaptureGranted {
                Label("macOS may hide window titles until Screen Recording is granted.", systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.visibleWindows.isEmpty {
                ContentUnavailableView("No windows reported", systemImage: "macwindow", description: Text("Open an app window, then refresh. Only on-screen, normal-level windows are listed."))
            } else {
                ManagementCard {
                    VStack(spacing: 0) {
                        ForEach(model.visibleWindows) { window in
                            HStack(spacing: 14) {
                                Image(systemName: "macwindow").foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(window.owner).fontWeight(.medium)
                                    Text(window.title.isEmpty ? "Title unavailable" : window.title)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(window.width) × \(window.height)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            if window.id != model.visibleWindows.last?.id { Divider() }
                        }
                    }
                }
            }
            Text("Snapshot only • Window order follows the desktop stacking order. Dimensions are reported by Core Graphics. No window is moved or captured by this page.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var diagnostics: some View {
        let runtime = model.runtimeStatus()
        return VStack(alignment: .leading, spacing: 22) {
            ManagementCard {
                VStack(spacing: 16) {
                    diagnosticRow("Metal renderer", value: runtime.metalAvailable ? "Available" : "Unavailable", healthy: runtime.metalAvailable)
                    Divider()
                    diagnosticRow("Event tap", value: runtime.eventTapRunning ? "Running" : "Not running", healthy: runtime.eventTapRunning)
                    Divider()
                    diagnosticRow("Accessibility", value: Permissions.accessibilityGranted(prompt: false) ? "Granted" : "Not granted", healthy: Permissions.accessibilityGranted(prompt: false))
                    Divider()
                    diagnosticRow("Screen Recording", value: Permissions.screenCaptureGranted ? "Granted" : "Not granted", healthy: Permissions.screenCaptureGranted)
                }
            }
            ManagementCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Configuration").font(.headline)
                    LabeledContent("Physics preset", value: model.settings.preset.title)
                    LabeledContent("Mesh", value: "\(model.settings.tilesX) × \(model.settings.tilesY)")
                    LabeledContent("Excluded apps", value: "\(model.settings.excludedApps.count)")
                    LabeledContent("Per-app effects", value: "\(model.settings.appCloseEffects.count)")
                    LabeledContent("System", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    LabeledContent("Version", value: version)
                }
            }
            Text("These checks reflect the current process, not measured frame rates or GPU utilization. If permissions are granted but the event tap is not running, relaunch Kinetiq.")
                .font(.callout).foregroundStyle(.secondary)
            permissionButtons
        }
    }

    private func diagnosticRow(_ title: String, value: String, healthy: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(value, systemImage: healthy ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(healthy ? .green : .orange)
        }
    }

    private func engineTitle(_ runtime: ManagementRuntimeStatus) -> String {
        if !runtime.metalAvailable { return "Metal unavailable" }
        if !model.settings.enabled { return "Paused" }
        if !Permissions.accessibilityGranted(prompt: false) || !Permissions.screenCaptureGranted { return "Needs permission" }
        return runtime.eventTapRunning ? "Running" : "Waiting for input"
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "—") · Build \(info["CFBundleVersion"] as? String ?? "—")"
    }
}

/// Shared surface styling adapts to both macOS light and dark appearances.
private struct ManagementCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.045)))
    }
}

private struct StatusCard: View {
    let title: String
    let symbol: String
    let value: String
    let healthy: Bool

    var body: some View {
        ManagementCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                Text(title).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(healthy ? Color.green : Color.orange).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(value).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}