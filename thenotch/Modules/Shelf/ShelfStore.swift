//
//  ShelfStore.swift
//  thenotch
//

import Foundation
import Observation

/// A file kept on the shelf.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    var url: URL
    let addedAt: Date
    /// Saved by the app (see `DroppedFile.isOwned`); deleted when it leaves
    /// the shelf. Otherwise the user's file, which is only referenced.
    let isOwned: Bool

    init(id: UUID = UUID(), url: URL, addedAt: Date = .now, isOwned: Bool = false) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.isOwned = isOwned
    }

    var name: String { url.lastPathComponent }
}

/// Files on the shelf, newest first. With `persistence`, they're read in
/// the background by `load()` and saved shortly after changes
/// (`saveDelay`), in the background.
@MainActor
@Observable
final class ShelfStore {
    /// Oldest items are dropped beyond this.
    static let maxItems = 50
    /// Changes in quick succession (a drop, then pruning…) are saved once.
    static let saveDelay: Duration = .seconds(1)

    private(set) var items: [ShelfItem] = [] {
        didSet { scheduleSave() }
    }
    /// The saved shelf has been read (always, without `persistence`).
    /// Nothing is saved before, so the file can't lose what's in it.
    @ObservationIgnored private(set) var isLoaded: Bool

    /// Called with items that left the shelf, so owned files can be deleted.
    @ObservationIgnored var onRemove: (([ShelfItem]) -> Void)?
    @ObservationIgnored private let persistence: ShelfPersistence?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false

    init(persistence: ShelfPersistence? = nil) {
        self.persistence = persistence
        isLoaded = persistence == nil
    }

    /// Reads the saved shelf in the background, once. Files added
    /// meanwhile stay in front of the saved ones.
    func load() async {
        guard let persistence, !isLoaded, !isLoading else { return }
        isLoading = true
        let saved = await persistence.loadInBackground()
        let added = items
        let known = Set(added.map { Self.key($0.url) })
        let all = added + saved.filter { !known.contains(Self.key($0.url)) }
        items = Array(all.prefix(Self.maxItems))  // not saved: not loaded yet
        isLoaded = true
        isLoading = false
        removed(Array(all.dropFirst(Self.maxItems)))
        if !added.isEmpty {
            scheduleSave()
        }
    }

    /// Adds files not already on the shelf, newest first, keeping the
    /// order they were dropped in. Returns how many were added.
    @discardableResult
    func add(_ files: [DroppedFile], now: Date = .now) -> Int {
        var known = Set(items.map { Self.key($0.url) })
        var added: [ShelfItem] = []
        for file in files where file.url.isFileURL && known.insert(Self.key(file.url)).inserted {
            added.append(ShelfItem(url: file.url, addedAt: now, isOwned: file.isOwned))
        }
        let all = added + items
        items = Array(all.prefix(Self.maxItems))
        removed(Array(all.dropFirst(Self.maxItems)))
        return added.count
    }

    func remove(_ id: ShelfItem.ID) {
        remove { $0.id == id }
    }

    func remove(_ ids: Set<ShelfItem.ID>) {
        remove { ids.contains($0.id) }
    }

    func removeAll() {
        remove { _ in true }
    }

    /// Drops items whose file no longer exists (deleted, or moved away).
    func removeMissing(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        remove { !exists($0.url) }
    }

    /// Drops items older than `lifetime` (`nil` keeps them forever).
    func removeExpired(lifetime: TimeInterval?, now: Date = .now) {
        guard let lifetime else { return }
        remove { $0.addedAt.addingTimeInterval(lifetime) <= now }
    }

    /// When the next item expires, if any.
    func nextExpiry(lifetime: TimeInterval?) -> Date? {
        guard let lifetime else { return nil }
        return items.map { $0.addedAt.addingTimeInterval(lifetime) }.min()
    }

    /// Writes a pending change right away, or waits for a save already
    /// under way (when the app quits or the shelf is switched off).
    func saveNow() {
        guard let pendingSave else {
            persistence?.waitForSaves()
            return
        }
        pendingSave.cancel()
        self.pendingSave = nil
        persistence?.saveNow(items)
    }

    private func scheduleSave() {
        guard persistence != nil, isLoaded else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard let self, !Task.isCancelled else { return }
            self.pendingSave = nil
            self.persistence?.saveInBackground(self.items)
        }
    }

    private func remove(where shouldRemove: (ShelfItem) -> Bool) {
        let gone = items.filter(shouldRemove)
        guard !gone.isEmpty else { return }
        items.removeAll(where: shouldRemove)
        removed(gone)
    }

    private func removed(_ gone: [ShelfItem]) {
        if !gone.isEmpty {
            onRemove?(gone)
        }
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
