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

/// Files on the shelf, newest first, saved by `persistence` on every change.
@MainActor
@Observable
final class ShelfStore {
    /// Oldest items are dropped beyond this.
    static let maxItems = 50

    private(set) var items: [ShelfItem] {
        didSet { persistence?.save(items) }
    }

    /// Called with items that left the shelf, so owned files can be deleted.
    @ObservationIgnored var onRemove: (([ShelfItem]) -> Void)?
    @ObservationIgnored private let persistence: ShelfPersistence?

    init(persistence: ShelfPersistence? = nil) {
        self.persistence = persistence
        items = persistence?.load() ?? []
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
