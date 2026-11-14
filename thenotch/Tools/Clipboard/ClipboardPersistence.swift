//
//  ClipboardPersistence.swift
//  thenotch
//

import CryptoKit
import Foundation
import os
import Security

/// Saves the clipboard history, sealed (`ClipboardCrypto`), in
/// `<directory>/History.sealed` and `<directory>/Images/<uuid>.sealed`. The
/// directories are 0700 (never followed if they're symlinks: replaced by a
/// real directory), the files 0600, and the directory is excluded from
/// backups. Every operation runs on one serial queue, in the order it was
/// asked for; the `…Now`, `read…` and `load` variants that return a value
/// wait for the earlier ones. Copies share the queue.
struct ClipboardPersistence: Sendable {
    /// How `load` went.
    enum LoadOutcome: Sendable, Equatable {
        /// The saved history was read.
        case loaded
        /// Nothing saved yet.
        case noHistory
        /// The index couldn't be opened (another key, damaged): everything
        /// was deleted, the history starts empty.
        case unreadableWiped
    }

    struct LoadResult: Sendable, Equatable {
        var items: [ClipboardItem]
        var outcome: LoadOutcome
        /// Image entries dropped because their blob was missing.
        var droppedItems = 0
        /// Blobs deleted because no entry referenced them.
        var removedOrphans = 0
    }

    /// How `wipeInBackground(then:)` went.
    struct WipeResult: Sendable {
        /// Nothing is left on disk.
        var filesRemoved: Bool
        /// What `then` returned, `nil` if it threw.
        var key: SymmetricKey?
        /// What `then` threw.
        var keyError: ClipboardKeyError?
    }

    let directory: URL
    private let queue: DispatchQueue

    /// `<directory>` is created when something is written.
    init(directory: URL) {
        self.directory = directory
        queue = DispatchQueue(label: AppIdentity.queueLabel("clipboard-persistence"), qos: .utility)
    }

    /// `~/Library/Application Support/<bundle id>/Clipboard/`. One instance,
    /// so every store (and Settings' Clear History) uses the same queue.
    static let standard = ClipboardPersistence(directory: AppIdentity.supportDirectory
        .appendingPathComponent("Clipboard", isDirectory: true))

    var indexURL: URL { directory.appendingPathComponent("History.sealed") }
    var imagesDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    func blobURL(_ id: UUID) -> URL {
        imagesDirectory.appendingPathComponent("\(id.uuidString).sealed")
    }

    // MARK: Index

    /// Saves the entries in the background.
    func saveIndex(_ items: [ClipboardItem], key: SymmetricKey) {
        queue.async { writeIndex(items, key: key) }
    }

    /// Saves the entries and returns once they're written, after the
    /// earlier operations. For quitting.
    func saveIndexNow(_ items: [ClipboardItem], key: SymmetricKey) {
        queue.sync { writeIndex(items, key: key) }
    }

    /// `load(key:)` in the background, after the earlier operations.
    func loadInBackground(key: SymmetricKey) async -> LoadResult {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: readAll(key: key)) }
        }
    }

    /// Reads the saved history, after the earlier operations. An index that
    /// can't be opened deletes everything. Blobs no entry references are
    /// deleted, and entries whose blob is missing dropped.
    func load(key: SymmetricKey) -> LoadResult {
        queue.sync { readAll(key: key) }
    }

    // MARK: Blobs

    func writeBlob(_ id: UUID, bytes: Data, key: SymmetricKey) {
        queue.async {
            do {
                let sealed = try ClipboardCrypto(key: key).seal(bytes, role: .blob, itemID: id)
                try prepareDirectory(imagesDirectory)
                try write(sealed, to: blobURL(id))
            } catch {
                Self.log.error("Couldn't save an image: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// The blob's bytes, after the earlier operations (so a blob being
    /// written is read once written). Throws if it's missing or can't be
    /// opened. Waits: don't call it on the main thread.
    func readBlob(_ id: UUID, key: SymmetricKey) throws -> Data {
        try queue.sync { try openBlob(id, key: key) }
    }

    /// `readBlob` in the background; `nil` if it can't be read.
    func readBlobInBackground(_ id: UUID, key: SymmetricKey) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: try? openBlob(id, key: key)) }
        }
    }

    func deleteBlobs(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        queue.async {
            for id in ids {
                try? FileManager.default.removeItem(at: blobURL(id))
            }
        }
    }

    // MARK: Whole store

    /// Deletes the directory and everything in it, in the background.
    func wipe() {
        queue.async { _ = removeDirectory() }
    }

    /// Deletes the directory and everything in it, after the earlier
    /// operations, and returns once done: whether nothing is left. For
    /// quitting.
    @discardableResult
    func wipeNow() -> Bool {
        queue.sync { removeDirectory() }
    }

    /// Deletes everything after the earlier operations, then runs `then`
    /// (replacing or deleting the key) on the queue, so later writes come
    /// after both. Off the main thread: the Keychain may wait.
    func wipeInBackground(
        then keyAction: @escaping @Sendable () throws -> SymmetricKey?
    ) async -> WipeResult {
        await withCheckedContinuation { continuation in
            queue.async {
                var result = WipeResult(filesRemoved: removeDirectory())
                do {
                    result.key = try keyAction()
                } catch let error as ClipboardKeyError {
                    result.keyError = error
                } catch {
                    result.keyError = .keychain(errSecInternalError)
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Whether anything is saved (the directory exists), after the earlier
    /// operations.
    func hasFilesInBackground() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.itemExists(directory)) }
        }
    }

    /// Returns once the earlier operations are done.
    func waitForPendingWrites() {
        queue.sync {}
    }

    // MARK: On the queue

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "clipboard")

    private struct Index: Codable {
        var version = 1
        var items: [ClipboardItem]
    }

    private func writeIndex(_ items: [ClipboardItem], key: SymmetricKey) {
        do {
            let plain = try JSONEncoder().encode(Index(items: items))
            let sealed = try ClipboardCrypto(key: key).seal(plain, role: .index, itemID: nil)
            try prepareDirectory(directory)
            try write(sealed, to: indexURL)
        } catch {
            Self.log.error("Couldn't save the history: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func readAll(key: SymmetricKey) -> LoadResult {
        let fileManager = FileManager.default
        guard let sealed = try? Data(contentsOf: indexURL) else {
            // No index: any blob left is an orphan.
            let removed = removeOrphans(keeping: [])
            return LoadResult(items: [], outcome: .noHistory, removedOrphans: removed)
        }
        let index: Index
        do {
            let plain = try ClipboardCrypto(key: key).open(sealed, role: .index, itemID: nil)
            index = try JSONDecoder().decode(Index.self, from: plain)
        } catch {
            Self.log.error("History unreadable, starting empty: \(String(describing: type(of: error)), privacy: .public)")
            _ = removeDirectory()
            return LoadResult(items: [], outcome: .unreadableWiped)
        }
        if Self.itemExists(directory) {
            try? prepareDirectory(directory)
        }
        var dropped = 0
        let items = index.items.filter { item in
            guard let blobID = item.blobID else { return true }
            let exists = fileManager.fileExists(atPath: blobURL(blobID).path)
            if !exists { dropped += 1 }
            return exists
        }
        let removed = removeOrphans(keeping: Set(items.compactMap(\.blobID)))
        if dropped > 0 || removed > 0 {
            Self.log.info("Cleaned up \(dropped) entries without image, \(removed) orphan images")
        }
        return LoadResult(items: items, outcome: .loaded, droppedItems: dropped, removedOrphans: removed)
    }

    private func openBlob(_ id: UUID, key: SymmetricKey) throws -> Data {
        let sealed = try Data(contentsOf: blobURL(id))
        return try ClipboardCrypto(key: key).open(sealed, role: .blob, itemID: id)
    }

    /// Deletes the blobs whose ID isn't in `kept` (and anything else in the
    /// images directory). Returns how many.
    private func removeOrphans(keeping kept: Set<UUID>) -> Int {
        let fileManager = FileManager.default
        // Never through a symlink: it would delete files elsewhere.
        guard Self.isRealDirectory(directory), Self.isRealDirectory(imagesDirectory),
              let names = try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path) else { return 0 }
        var removed = 0
        for name in names {
            let isKept = name.hasSuffix(".sealed")
                && UUID(uuidString: String(name.dropLast(".sealed".count))).map(kept.contains) == true
            guard !isKept else { continue }
            if (try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(name))) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// Deletes the directory (a symlink in its place: the link only).
    /// Returns whether nothing is left.
    private func removeDirectory() -> Bool {
        guard Self.itemExists(directory) else { return true }
        do {
            try FileManager.default.removeItem(at: directory)
            return true
        } catch {
            Self.log.error("Couldn't delete the history: \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
    }

    /// Something is at `url` (a dangling symlink too: not followed).
    private static func itemExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// A directory, not a symlink to one.
    private static func isRealDirectory(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeDirectory
    }

    /// Creates `url` (and the main directory) with 0700, or sets 0700 if
    /// it exists with other permissions. Something else in its place (a
    /// symlink, a file) is removed, never followed. The main directory is
    /// excluded from backups.
    private func prepareDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        for dir in Set([directory, url]).sorted(by: { $0.path.count < $1.path.count }) {
            // `attributesOfItem` doesn't follow a symlink.
            if let attributes = try? fileManager.attributesOfItem(atPath: dir.path) {
                if attributes[.type] as? FileAttributeType == .typeDirectory {
                    if (attributes[.posixPermissions] as? NSNumber)?.int16Value != 0o700 {
                        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
                    }
                } else {
                    Self.log.error("Replacing a non-directory where the history goes")
                    try fileManager.removeItem(at: dir)
                    try createPrivateDirectory(dir)
                }
            } else {
                try createPrivateDirectory(dir)
            }
            if dir == directory { excludeFromBackup(dir) }
        }
    }

    private func createPrivateDirectory(_ dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Every time, in case it was cleared (a restore, a copy).
    private func excludeFromBackup(_ dir: URL) {
        var url = dir
        url.removeCachedResourceValue(forKey: .isExcludedFromBackupKey)
        guard (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true
        else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Atomically, then 0600 (inside a 0700 directory, so never readable
    /// by others meanwhile).
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
