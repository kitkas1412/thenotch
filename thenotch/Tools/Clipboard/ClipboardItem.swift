//
//  ClipboardItem.swift
//  thenotch
//

import CoreGraphics
import CryptoKit
import Foundation

/// An entry of the clipboard history. Saved only inside the encrypted index
/// (`ClipboardPersistence`); an image's bytes are a separate encrypted blob.
struct ClipboardItem: Identifiable, Codable, Sendable, Equatable {
    enum Content: Codable, Sendable, Equatable {
        /// Plain text, with the rich versions copied alongside it, if any.
        case text(plain: String, rtf: Data?, html: Data?)
        /// The image's bytes are the blob `blobID`, in the format `uti`.
        case image(blobID: UUID, pixelSize: CGSize, uti: String, byteCount: Int)
        /// File paths only, never the files' contents.
        case files([String])
    }

    let id: UUID
    let createdAt: Date
    var lastUsedAt: Date
    let content: Content
    /// The app that put it on the pasteboard, when it said so.
    let sourceBundleID: String?
    /// SHA-256 (hex) of the normalized content (`ClipboardItem.hash`), to
    /// find duplicates.
    let contentHash: String

    init(
        id: UUID = UUID(),
        createdAt: Date,
        lastUsedAt: Date? = nil,
        content: Content,
        sourceBundleID: String?,
        contentHash: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.content = content
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash
    }

    /// The image blob this item references, if any.
    var blobID: UUID? {
        if case .image(let blobID, _, _, _) = content { return blobID }
        return nil
    }

    /// The image's size in bytes (0 for other content).
    var imageByteCount: Int {
        if case .image(_, _, _, let byteCount) = content { return byteCount }
        return 0
    }

    // MARK: Hashing

    /// Text is compared by its plain version only (the same words copied
    /// from two apps are one entry).
    static func hash(text plain: String) -> String {
        hash(kind: "text", Data(plain.utf8))
    }

    /// The image's bytes, whatever its size.
    static func hash(image bytes: Data) -> String {
        hash(kind: "image", bytes)
    }

    /// The paths, in order.
    static func hash(files paths: [String]) -> String {
        hash(kind: "files", Data(paths.joined(separator: "\u{0}").utf8))
    }

    private static func hash(kind: String, _ payload: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: payload)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
