// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import KinetiqCore
import UniformTypeIdentifiers

/// A local, user-readable-only desktop scene. The native host never requests capture permission.
public struct SaverArchive: Codable, Sendable {
    public struct Window: Codable, Sendable {
        public let frame: CGRect
        public let image: Data
        public let isDock: Bool

        public init(frame: CGRect, image: CGImage, isDock: Bool) throws {
            self.frame = frame
            self.image = try SaverArchive.png(image)
            self.isDock = isDock
        }
    }

    public struct Display: Codable, Sendable {
        public let id: UInt32
        public let size: CGSize
        public let wallpaper: Data
        public let windows: [Window]

        public init(id: UInt32, size: CGSize, wallpaper: CGImage, windows: [Window]) throws {
            self.id = id
            self.size = size
            self.wallpaper = try SaverArchive.png(wallpaper)
            self.windows = windows
        }

        /// Reuses the same extraction and physics scene builder as the in-app preview.
        public func scene() -> ChaosScene {
            let inputs = windows.compactMap { window -> ChaosWindowInput? in
                    guard window.frame.width.isFinite, window.frame.height.isFinite,
                        window.frame.origin.x.isFinite, window.frame.origin.y.isFinite,
                        window.frame.width > 0, window.frame.height > 0,
                      let image = SaverArchive.image(window.image),
                      let extraction = UIObjectExtractor.extract(from: image, size: window.frame.size, role: window.isDock ? .dock : .app)
                else { return nil }
                return ChaosWindowInput(frame: window.frame, extraction: extraction)
            }
            return ChaosSceneBuilder.build(windows: inputs)
        }
    }

    public let schema: Int
    public let capturedAt: Date
    public let displays: [Display]
    public let eventInterval: Double
    public let lifetime: Double
    public let intensity: Double
    public let speed: Double

    public var settings: ChaosSettings {
        ChaosSettings(eventInterval: eventInterval, lifetime: lifetime, intensity: intensity, speed: speed)
    }

    public init(displays: [Display], settings: ChaosSettings, capturedAt: Date = Date()) {
        schema = 1
        self.capturedAt = capturedAt
        self.displays = displays
        eventInterval = settings.eventInterval
        lifetime = settings.lifetime
        intensity = settings.intensity
        speed = settings.speed
    }

    /// Resolve the real user's home, not legacyScreenSaver's sandbox-relative home directory.
    public static var directory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/io.github.invernomut0.Kinetiq/SystemSaver", isDirectory: true)
    }

    public static var url: URL { directory.appendingPathComponent("desktop.plist") }

    public func write(to url: URL = SaverArchive.url) throws {
        guard !displays.isEmpty else { throw ArchiveError.noDisplays }
        guard isValid else { throw ArchiveError.invalidArchive }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(self)
        guard data.count <= 256 * 1024 * 1024 else { throw ArchiveError.invalidArchive }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        // The atomic temporary file inherits the private parent directory; never expose partial captures.
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func read(from url: URL = SaverArchive.url) throws -> SaverArchive {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= 256 * 1024 * 1024 else { throw ArchiveError.invalidArchive }
        let archive = try PropertyListDecoder().decode(SaverArchive.self, from: Data(contentsOf: url))
        guard archive.isValid else { throw ArchiveError.invalidArchive }
        return archive
    }

    private var isValid: Bool {
        guard schema == 1, !displays.isEmpty, displays.count <= 16,
              [eventInterval, lifetime, intensity, speed].allSatisfy(\.isFinite) else { return false }
        return displays.allSatisfy { display in
            guard display.size.width.isFinite, display.size.height.isFinite,
                  display.size.width > 0, display.size.height > 0,
                  display.size.width <= 32768, display.size.height <= 32768,
                  display.windows.count <= 24 else { return false }
            return display.windows.allSatisfy { window in
                let frame = window.frame
                return frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
                    && frame.width > 0 && frame.height > 0 && frame.width <= 32768 && frame.height <= 32768
            }
        }
    }

    public static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32768, height <= 32768,
              width * height <= 128 * 1024 * 1024 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ArchiveError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ArchiveError.invalidImage }
        return data as Data
    }

    public enum ArchiveError: Error { case noDisplays, invalidArchive, invalidImage }
}