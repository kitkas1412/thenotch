//
//  ClipboardTestSupport.swift
//  thenotchTests
//

import AppKit
import CryptoKit
import Foundation
@testable import thenotch

enum ClipboardFixtures {
    /// A valid 1x1 PNG.
    static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    /// A valid TIFF, made from the PNG.
    static var tiff: Data { NSBitmapImageRep(data: png)!.tiffRepresentation! }

    static func textItem(
        _ text: String, at seconds: TimeInterval = 0, id: UUID = UUID()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id, createdAt: Date(timeIntervalSince1970: seconds),
            content: .text(plain: text, rtf: nil, html: nil),
            sourceBundleID: nil, contentHash: ClipboardItem.hash(text: text))
    }

    static func imageItem(
        bytes: Int, tag: String = UUID().uuidString, at seconds: TimeInterval = 0, blobID: UUID = UUID()
    ) -> ClipboardItem {
        ClipboardItem(
            createdAt: Date(timeIntervalSince1970: seconds),
            content: .image(blobID: blobID, pixelSize: CGSize(width: 1, height: 1), uti: "public.png", byteCount: bytes),
            sourceBundleID: nil, contentHash: ClipboardItem.hash(image: Data(tag.utf8)))
    }

    static func textDraft(_ text: String) -> ClipboardDraft {
        ClipboardDraft(content: .text(plain: text, rtf: nil, html: nil), sourceBundleID: nil)
    }

    static func imageDraft(_ bytes: Data = png) -> ClipboardDraft {
        ClipboardDraft(content: .image(bytes: bytes, pixelSize: CGSize(width: 1, height: 1), uti: "public.png"),
                       sourceBundleID: nil)
    }

    /// A unique directory under the temporary directory; removed by `remove()`.
    static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("thenotchTests-clipboard-\(UUID().uuidString)", isDirectory: true)
    }

    static func permissions(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }
}

/// A key held in memory, for tests. `failure` makes every call throw it;
/// `readFailure` only `key()`. `onKey` runs at the start of `key()` (off
/// the main thread when the store loads), to hold a load mid-way.
final class InMemoryKeyStore: ClipboardKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SymmetricKey?
    private var _failure: ClipboardKeyError?
    private var _readFailure: ClipboardKeyError?
    private var _onKey: (@Sendable () -> Void)?

    init(key: SymmetricKey? = nil, failure: ClipboardKeyError? = nil, readFailure: ClipboardKeyError? = nil) {
        stored = key
        _failure = failure
        _readFailure = readFailure
    }

    var failure: ClipboardKeyError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var readFailure: ClipboardKeyError? {
        get { lock.withLock { _readFailure } }
        set { lock.withLock { _readFailure = newValue } }
    }

    var onKey: (@Sendable () -> Void)? {
        get { lock.withLock { _onKey } }
        set { lock.withLock { _onKey = newValue } }
    }

    /// The current key, without creating one.
    var currentKey: SymmetricKey? { lock.withLock { stored } }

    func key() throws -> SymmetricKey {
        onKey?()
        return try lock.withLock {
            if let _failure { throw _failure }
            if let _readFailure { throw _readFailure }
            if let stored { return stored }
            let key = SymmetricKey(size: .bits256)
            stored = key
            return key
        }
    }

    func rotate() throws -> SymmetricKey {
        try lock.withLock {
            if let _failure { throw _failure }
            let key = SymmetricKey(size: .bits256)
            stored = key
            return key
        }
    }

    func delete() throws {
        try lock.withLock {
            if let _failure { throw _failure }
            stored = nil
        }
    }
}
