//
//  ShelfThumbnails.swift
//  thenotch
//

import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnails of shelf files, kept between openings of the
/// island: its content is rebuilt each time it opens, and generating a
/// thumbnail reads and decodes the file.
///
/// Keyed by path and scale, so a file edited while on the shelf keeps its
/// old thumbnail until it leaves the cache.
@MainActor
enum ShelfThumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = ShelfStore.maxItems
        return cache
    }()

    static func cached(for url: URL, scale: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, scale))
    }

    /// The cached thumbnail, or a new one; `nil` if Quick Look has none.
    static func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        if let cached = cached(for: url, scale: scale) {
            return cached
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: key(url, scale))
        return image
    }

    private static func key(_ url: URL, _ scale: CGFloat) -> NSString {
        "\(url.standardizedFileURL.path)@\(scale)" as NSString
    }
}
