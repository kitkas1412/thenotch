//
//  ClipboardHistory.swift
//  thenotch
//

import Foundation

/// The history's entries, newest (or last used) first, kept within `limit`
/// entries and `maxImageBytes` of images. Pure: changes return the image
/// blobs no longer referenced, for the caller to delete.
struct ClipboardHistory: Sendable, Equatable {
    /// Images beyond this total are dropped, oldest first.
    static let maxImageBytes = 200_000_000

    private(set) var items: [ClipboardItem]
    /// At most this many entries (at least 1).
    private(set) var limit: Int

    init(items: [ClipboardItem] = [], limit: Int) {
        self.items = items
        self.limit = max(1, limit)
    }

    var imageBytes: Int { items.reduce(0) { $0 + $1.imageByteCount } }

    /// Puts `item` on top. When an entry has the same `contentHash`, that
    /// one moves to the top instead (used at `item.lastUsedAt`) and `item`
    /// is discarded, with its blob. Returns the blobs no longer referenced.
    @discardableResult
    mutating func insert(_ item: ClipboardItem) -> [UUID] {
        let before = blobIDs
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: index)
            existing.lastUsedAt = max(existing.lastUsedAt, item.lastUsedAt)
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        trim()
        return unreferenced(since: before)
    }

    /// The entry kept for `item` by `insert`: `item` itself, or the
    /// duplicate it was merged into, unless it was evicted at once.
    func entry(for item: ClipboardItem) -> ClipboardItem? {
        items.first { $0.contentHash == item.contentHash }
    }

    /// Drops the oldest entries beyond `limit`, which becomes the limit.
    @discardableResult
    mutating func evict(toLimit limit: Int) -> [UUID] {
        let before = blobIDs
        self.limit = max(1, limit)
        trim()
        return unreferenced(since: before)
    }

    @discardableResult
    mutating func remove(_ id: ClipboardItem.ID) -> [UUID] {
        let before = blobIDs
        items.removeAll { $0.id == id }
        return unreferenced(since: before)
    }

    /// Moves the entry to the top, used at `now`.
    mutating func markUsed(_ id: ClipboardItem.ID, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.lastUsedAt = now
        items.insert(item, at: 0)
    }

    @discardableResult
    mutating func clear() -> [UUID] {
        let before = blobIDs
        items = []
        return unreferenced(since: before)
    }

    private var blobIDs: Set<UUID> { Set(items.compactMap(\.blobID)) }

    private func unreferenced(since before: Set<UUID>) -> [UUID] {
        let now = blobIDs
        // Sorted, for stable results.
        return before.subtracting(now).sorted { $0.uuidString < $1.uuidString }
    }

    private mutating func trim() {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        var total = imageBytes
        while total > Self.maxImageBytes,
              let index = items.lastIndex(where: { $0.imageByteCount > 0 }) {
            total -= items[index].imageByteCount
            items.remove(at: index)
        }
    }
}
