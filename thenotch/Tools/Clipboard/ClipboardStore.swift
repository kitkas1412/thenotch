//
//  ClipboardStore.swift
//  thenotch
//

import CryptoKit
import Foundation
import Observation
import os

/// The clipboard history, newest (or last used) first. With `persistence`,
/// `load()` gets the key and reads the saved history in the background;
/// changes are saved shortly after (`saveDelay`), sealed. Nothing is
/// written before `load()` finishes: images copied meanwhile wait in memory.
/// Without a key (Keychain denied, locked…), the history lives in memory
/// only, the saved one is left alone, and the next `load()` tries again.
///
/// The key, on `load()`:
///
/// | `keyProvider.key()`                        | Files      | Keychain item     | Issue             |
/// |--------------------------------------------|------------|-------------------|-------------------|
/// | a key, the index opens                     | read       | kept              | none              |
/// | a key, the index fails to open (or decode) | deleted    | kept              | `.startedFresh`   |
/// | none stored (created by `key()`)           | as above: an old index can't open, so deleted | |
/// | `invalidKeyData` (not a 256-bit key)       | deleted    | deleted, replaced | `.startedFresh`   |
/// | `invalidKeyData`, and replacing it fails   | deleted    | —                 | `.keyUnavailable` |
/// | any other error (prompt denied, interaction not allowed, locked, other OSStatus) | kept | kept | `.keyUnavailable`, retried by the next `load()` |
///
/// `clear()` deletes the files and replaces the key on the persistence
/// queue (off the main thread, in order with the writes); until the new key
/// is there, changes stay in memory. `clearNow()` does it synchronously, for
/// quitting. A store replaced by another (the tool stopped) is `discard()`ed:
/// it doesn't touch the disk or the Keychain any more.
@MainActor
@Observable
final class ClipboardStore {
    /// Why the history isn't what was saved, for Settings to say.
    enum StorageIssue: Sendable, Equatable {
        /// The key couldn't be read or created: the history isn't saved
        /// (what was saved is kept; the next `load()` tries again).
        case keyUnavailable
        /// The saved history couldn't be read (key lost or replaced,
        /// damaged): it was deleted.
        case startedFresh
        /// Clearing couldn't delete every saved file.
        case notDeleted
        /// Clearing couldn't delete every saved file, nor replace the key:
        /// like `keyUnavailable`, the next `load()` tries again.
        case notDeletedKeyUnavailable

        /// What Settings and the panel say.
        var message: String {
            switch self {
            case .keyUnavailable: "History couldn't be unlocked — new items are kept until you quit."
            case .startedFresh: "Earlier history couldn't be read and was removed."
            case .notDeleted: "Some saved history couldn't be deleted. Try Clear History again."
            case .notDeletedKeyUnavailable:
                "Some saved history couldn't be deleted, and its key couldn't be replaced — new items are kept until you quit. Try Clear History again."
            }
        }

        /// No key: the history isn't saved, and `load()` retries.
        var isKeyUnavailable: Bool {
            switch self {
            case .keyUnavailable, .notDeletedKeyUnavailable: true
            case .startedFresh, .notDeleted: false
            }
        }
    }

    /// Changes in quick succession are saved once.
    static let saveDelay: Duration = .seconds(1)

    private(set) var items: [ClipboardItem] = []
    /// The saved history has been read (always, without `persistence`).
    private(set) var isLoaded: Bool
    private(set) var lastStorageIssue: StorageIssue?
    var limit: Int { history.limit }

    @ObservationIgnored private var history: ClipboardHistory {
        didSet { items = history.items }
    }
    @ObservationIgnored private let persistence: ClipboardPersistence?
    @ObservationIgnored private let keyProvider: ClipboardKeyProviding
    /// Set once loaded with a usable key: files are written only then.
    @ObservationIgnored private var key: SymmetricKey?
    /// Image bytes not on disk: before loading, or without a key.
    @ObservationIgnored private var memoryBlobs: [UUID: Data] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false
    /// `clear()` ran while loading: what's read is dropped, the key replaced.
    @ObservationIgnored private var clearedWhileLoading = false
    /// Bumped by each key replacement; only the latest one is applied.
    @ObservationIgnored private var keyGeneration = 0
    /// Replaced by another store: nothing touches the disk or the Keychain.
    @ObservationIgnored private(set) var isDiscarded = false

    private nonisolated static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "clipboard")

    init(persistence: ClipboardPersistence?, keyProvider: ClipboardKeyProviding, limit: Int) {
        self.persistence = persistence
        self.keyProvider = keyProvider
        history = ClipboardHistory(limit: limit)
        isLoaded = persistence == nil
    }

    /// Whether changes are written to disk.
    var isPersistent: Bool { persistence != nil && key != nil }

    // MARK: Loading

    private enum KeyResolution: Sendable {
        case key(SymmetricKey)
        /// The stored key was invalid: a new one, the old files are useless.
        case fresh(SymmetricKey)
        /// The stored key was invalid and couldn't be replaced.
        case invalidUnreplaceable
        /// The key couldn't be read, maybe only for now.
        case unavailable

        var isFresh: Bool {
            if case .fresh = self { return true }
            return false
        }
    }

    /// Without a key yet, because it couldn't be read: `load()` retries.
    private var needsKeyRetry: Bool {
        persistence != nil && key == nil && lastStorageIssue?.isKeyUnavailable == true
    }

    /// Gets the key (off the main thread: the Keychain may wait) and reads
    /// the saved history in the background, once (again while the key is
    /// unavailable). Entries added meanwhile stay in front of the saved ones.
    func load() async {
        guard let persistence, !isDiscarded, !isLoaded || needsKeyRetry, !isLoading else { return }
        isLoading = true
        let provider = keyProvider
        let resolution = await Task.detached(priority: .utility) {
            Self.resolveKey(provider)
        }.value
        guard !isDiscarded else {
            isLoading = false
            return
        }

        var saved: [ClipboardItem] = []
        var changed = false
        switch resolution {
        case .key(let key):
            let result = await persistence.loadInBackground(key: key)
            guard !isDiscarded else {
                isLoading = false
                return
            }
            self.key = key
            saved = result.items
            changed = result.droppedItems > 0
            if result.outcome == .unreadableWiped {
                lastStorageIssue = .startedFresh
            } else if lastStorageIssue?.isKeyUnavailable == true {
                lastStorageIssue = nil
            }
        case .fresh(let key):
            persistence.wipe()
            self.key = key
            lastStorageIssue = .startedFresh
        case .invalidUnreplaceable:
            persistence.wipe()
            lastStorageIssue = .keyUnavailable
            Self.log.error("No key for the clipboard history: kept in memory only")
        case .unavailable:
            // Maybe temporary: the saved history and the key are left alone.
            lastStorageIssue = .keyUnavailable
            Self.log.error("Clipboard key unavailable: kept in memory only, retried on next load")
        }

        if clearedWhileLoading {
            clearedWhileLoading = false
            saved = []
            changed = false
            if self.key != nil {
                // Changes wait in memory until the new key is there.
                replaceKey()
            }
        }

        let added = history.items
        var merged = ClipboardHistory(items: saved, limit: history.limit)
        var evicted = merged.evict(toLimit: history.limit)
        for item in added.reversed() {
            evicted += merged.insert(item)
        }
        history = merged
        isLoaded = true
        isLoading = false

        // Images copied while loading (minus duplicates of saved ones), now
        // that they can be written.
        let referenced = Set(merged.items.compactMap(\.blobID))
        memoryBlobs = memoryBlobs.filter { referenced.contains($0.key) }
        if let key {
            for (id, bytes) in memoryBlobs {
                persistence.writeBlob(id, bytes: bytes, key: key)
            }
            memoryBlobs = [:]
        }
        discardBlobs(evicted)
        if !added.isEmpty || !evicted.isEmpty || changed || resolution.isFresh {
            scheduleSave()
        }
    }

    private nonisolated static func resolveKey(_ provider: ClipboardKeyProviding) -> KeyResolution {
        do {
            return .key(try provider.key())
        } catch ClipboardKeyError.invalidKeyData {
            log.error("Clipboard key invalid, replacing it")
        } catch {
            log.error("Clipboard key unreadable: \(Self.describe(error), privacy: .public)")
            return .unavailable
        }
        do {
            try? provider.delete()
            return .fresh(try provider.rotate())
        } catch {
            log.error("Clipboard key can't be replaced: \(Self.describe(error), privacy: .public)")
            return .invalidUnreplaceable
        }
    }

    private nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case ClipboardKeyError.keychain(let status): "OSStatus \(status)"
        case ClipboardKeyError.randomFailed(let status): "random OSStatus \(status)"
        case ClipboardKeyError.invalidKeyData: "invalid key data"
        default: String(describing: type(of: error))
        }
    }

    // MARK: Changes

    /// Records a copy (a duplicate moves the existing entry to the top).
    /// Returns the entry's ID, or `nil` if it was evicted at once.
    @discardableResult
    func add(_ draft: ClipboardDraft, now: Date = .now) -> ClipboardItem.ID? {
        guard !isDiscarded else { return nil }
        let item = draft.makeItem(now: now)
        var next = history
        let evicted = next.insert(item)
        let kept = next.entry(for: item)
        if kept?.id == item.id, let blobID = item.blobID, let bytes = draft.imageBytes {
            if let key, let persistence, isLoaded {
                // Before the index that references it.
                persistence.writeBlob(blobID, bytes: bytes, key: key)
            } else {
                memoryBlobs[blobID] = bytes
            }
        }
        history = next
        discardBlobs(evicted)
        scheduleSave()
        return kept?.id
    }

    func remove(_ id: ClipboardItem.ID) {
        let evicted = history.remove(id)
        discardBlobs(evicted)
        scheduleSave()
    }

    /// Moves the entry to the top (it was pasted).
    func markUsed(_ id: ClipboardItem.ID, now: Date = .now) {
        history.markUsed(id, now: now)
        scheduleSave()
    }

    /// Keeps at most `limit` entries, dropping the oldest.
    func setLimit(_ limit: Int) {
        guard max(1, limit) != history.limit else { return }
        let evicted = history.evict(toLimit: limit)
        discardBlobs(evicted)
        scheduleSave()
    }

    /// Deletes the history and its files, and replaces the key, so nothing
    /// sealed with the old one can be opened again. Both happen on the
    /// persistence queue; the returned task ends once they're done (`nil`:
    /// nothing to wait for). A failure shows as `lastStorageIssue`.
    @discardableResult
    func clear() -> Task<Void, Never>? {
        guard !isDiscarded else { return nil }
        forgetHistory()
        guard let persistence else { return nil }
        guard isLoaded, !isLoading else {
            persistence.wipe()
            clearedWhileLoading = isLoading
            return nil
        }
        return replaceKey()
    }

    /// `clear()` that returns once the files are deleted and the key with
    /// them (the next start creates a new one). For quitting: the app exits
    /// right after, so nothing may be left on a queue.
    func clearNow() {
        guard !isDiscarded else { return }
        forgetHistory()
        guard let persistence else { return }
        keyGeneration += 1
        key = nil
        if !persistence.wipeNow() {
            Self.log.error("Clipboard history not fully deleted on quit")
        }
        do {
            try keyProvider.delete()
        } catch {
            Self.log.error("Clipboard key can't be deleted: \(Self.describe(error), privacy: .public)")
        }
    }

    /// Stops using the disk and the Keychain: the store was replaced. A
    /// `load()` under way returns without applying what it read.
    func discard() {
        isDiscarded = true
        pendingSave?.cancel()
        pendingSave = nil
    }

    /// Whether anything is saved on disk (after the queued operations).
    func hasSavedFiles() async -> Bool {
        guard let persistence else { return false }
        return await persistence.hasFilesInBackground()
    }

    private func forgetHistory() {
        pendingSave?.cancel()
        pendingSave = nil
        history.clear()
        memoryBlobs = [:]
        ClipboardThumbnails.shared.removeAll()
        switch lastStorageIssue {
        case .startedFresh, .notDeleted: lastStorageIssue = nil
        case .notDeletedKeyUnavailable: lastStorageIssue = .keyUnavailable
        case .keyUnavailable, nil: break
        }
    }

    /// Deletes the files and replaces the key on the persistence queue.
    /// Meanwhile there's no key, so changes stay in memory.
    @discardableResult
    private func replaceKey() -> Task<Void, Never>? {
        guard let persistence else { return nil }
        key = nil
        keyGeneration += 1
        let generation = keyGeneration
        let provider = keyProvider
        return Task { [weak self] in
            let result = await persistence.wipeInBackground { try provider.rotate() }
            guard let self, !self.isDiscarded, self.keyGeneration == generation else { return }
            self.keyReplaced(result)
        }
    }

    private func keyReplaced(_ result: ClipboardPersistence.WipeResult) {
        key = result.key
        if let error = result.keyError {
            Self.log.error("Clipboard key can't be replaced: \(Self.describe(error), privacy: .public)")
        }
        switch (result.filesRemoved, result.keyError == nil) {
        case (false, false): lastStorageIssue = .notDeletedKeyUnavailable
        case (false, true): lastStorageIssue = .notDeleted
        case (true, false): lastStorageIssue = .keyUnavailable
        case (true, true):
            if lastStorageIssue?.isKeyUnavailable == true { lastStorageIssue = nil }
        }
        guard let key, let persistence else { return }
        // What was added meanwhile.
        let referenced = Set(history.items.compactMap(\.blobID))
        for (id, bytes) in memoryBlobs where referenced.contains(id) {
            persistence.writeBlob(id, bytes: bytes, key: key)
        }
        memoryBlobs = [:]
        if !history.items.isEmpty { scheduleSave() }
    }

    /// The image's bytes (decrypted in the background, never cached on
    /// disk), or `nil` if it can't be read.
    func imageData(for item: ClipboardItem) async -> Data? {
        guard let blobID = item.blobID else { return nil }
        if let bytes = memoryBlobs[blobID] { return bytes }
        guard let persistence, let key else { return nil }
        return await persistence.readBlobInBackground(blobID, key: key)
    }

    // MARK: Saving

    /// Writes a pending change right away, or waits for the writes under
    /// way (when the app quits or the tool stops).
    func saveNow() {
        guard let persistence, !isDiscarded else { return }
        guard let pendingSave, let key else {
            persistence.waitForPendingWrites()
            return
        }
        pendingSave.cancel()
        self.pendingSave = nil
        persistence.saveIndexNow(history.items, key: key)
    }

    private func scheduleSave() {
        guard persistence != nil, key != nil, isLoaded, !isDiscarded else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard let self, !Task.isCancelled, !self.isDiscarded else { return }
            self.pendingSave = nil
            guard let persistence = self.persistence, let key = self.key else { return }
            persistence.saveIndex(self.history.items, key: key)
        }
    }

    /// Forgets blobs no entry references any more, in memory and on disk.
    private func discardBlobs(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            memoryBlobs[id] = nil
        }
        if isPersistent, isLoaded, !isDiscarded {
            persistence?.deleteBlobs(ids)
        }
    }
}
