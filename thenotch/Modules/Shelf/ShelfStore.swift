//
//  ShelfStore.swift
//  thenotch
//

import Foundation
import Observation

/// A file kept on the shelf. The shelf only references the file; it
/// never copies or moves it.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    var name: String { url.lastPathComponent }
}

/// Files on the shelf, newest first. Kept in memory only for now.
@MainActor
@Observable
final class ShelfStore {
    /// Oldest items are dropped beyond this.
    static let maxItems = 50

    private(set) var items: [ShelfItem] = []

    /// Adds file URLs not already on the shelf, newest first, keeping the
    /// order they were dropped in. Returns how many were added.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var known = Set(items.map { Self.key($0.url) })
        var added: [ShelfItem] = []
        for url in urls where url.isFileURL {
            if known.insert(Self.key(url)).inserted {
                added.append(ShelfItem(url: url))
            }
        }
        items = Array((added + items).prefix(Self.maxItems))
        return added.count
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        items.removeAll()
    }

    /// Drops items whose file no longer exists (deleted, or moved away).
    func removeMissing(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        items.removeAll { !exists($0.url) }
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
