//
//  ShelfPersistence.swift
//  thenotch
//

import Foundation

/// Saves the shelf as JSON. Files are stored as bookmarks, which follow a
/// file that is renamed or moved while the app isn't running.
struct ShelfPersistence {
    let fileURL: URL

    /// `~/Library/Application Support/<bundle id>/Shelf.json`
    static var standard: ShelfPersistence {
        ShelfPersistence(fileURL: URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "thenotch", isDirectory: true)
            .appendingPathComponent("Shelf.json"))
    }

    private struct Record: Codable {
        var id: UUID
        var bookmark: Data?
        /// Fallback if the bookmark can't be created or resolved.
        var path: String
        var addedAt: Date
        var isOwned: Bool
    }

    func save(_ items: [ShelfItem]) {
        let records = items.map { item in
            Record(
                id: item.id,
                bookmark: try? item.url.bookmarkData(),
                path: item.url.path,
                addedAt: item.addedAt,
                isOwned: item.isOwned
            )
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // Losing the shelf on the next launch isn't worth interrupting the user.
        }
    }

    /// Saved items whose file can still be found.
    func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records.compactMap { record in
            guard let url = Self.resolve(record) else { return nil }
            return ShelfItem(id: record.id, url: url, addedAt: record.addedAt, isOwned: record.isOwned)
        }
    }

    private static func resolve(_ record: Record) -> URL? {
        if let bookmark = record.bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        let url = URL(fileURLWithPath: record.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
