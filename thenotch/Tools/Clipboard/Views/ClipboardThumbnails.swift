//
//  ClipboardThumbnails.swift
//  thenotch
//

import AppKit
import ImageIO

/// Image thumbnails and source-app icons for the rows, kept in memory only
/// (the store decrypts the image on every read).
@MainActor
final class ClipboardThumbnails {
    static let shared = ClipboardThumbnails()

    private let images = NSCache<NSUUID, NSImage>()
    private var icons: [String: NSImage?] = [:]
    /// Bumped by `removeAll()`: a decode started before isn't cached.
    private(set) var generation = 0

    private struct Box: @unchecked Sendable { let image: CGImage? }

    init() {
        images.countLimit = 80
    }

    func thumbnail(for item: ClipboardItem, store: ClipboardStore, side: CGFloat, scale: CGFloat) async -> NSImage? {
        guard let blobID = item.blobID else { return nil }
        let started = generation
        let key = blobID as NSUUID
        if let cached = images.object(forKey: key) { return cached }
        guard let data = await store.imageData(for: item) else { return nil }
        let pixels = Int(side * scale)
        let box = await Task.detached(priority: .utility) { Box(image: Self.downsample(data, maxPixels: pixels)) }.value
        guard let cgImage = box.image else { return nil }
        let image = NSImage(cgImage: cgImage, size: CGSize(width: side, height: side))
        // Cleared meanwhile: shown to the caller (if still there), not kept.
        guard generation == started else { return image }
        images.setObject(image, forKey: key)
        return image
    }

    private nonisolated static func downsample(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Forgets every cached thumbnail and icon (the history was cleared or
    /// the tool stopped).
    func removeAll() {
        generation += 1
        images.removeAllObjects()
        icons = [:]
    }

    /// The icon of the app with this bundle ID, if it's installed.
    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let known = icons[bundleID] { return known }
        var icon: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        icons[bundleID] = icon
        return icon
    }
}
