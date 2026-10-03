//
//  ShelfStoreTests.swift
//  thenotchTests
//

import AppKit
import Foundation
import Testing
@testable import thenotch

@MainActor
struct ShelfStoreTests {
    let store = ShelfStore()
    let a = URL(fileURLWithPath: "/tmp/a.txt")
    let b = URL(fileURLWithPath: "/tmp/b.png")
    let c = URL(fileURLWithPath: "/tmp/c.pdf")

    func files(_ urls: URL...) -> [DroppedFile] {
        urls.map { DroppedFile(url: $0, isOwned: false) }
    }

    @Test func newestDropComesFirstInDropOrder() {
        store.add(files(a))
        store.add(files(b, c))
        #expect(store.items.map(\.url) == [b, c, a])
    }

    @Test func duplicatesAreSkipped() {
        store.add(files(a, b))
        let added = store.add(files(URL(fileURLWithPath: "/tmp/./a.txt"), c, c))
        #expect(added == 1)
        #expect(store.items.map(\.url) == [c, a, b])
    }

    @Test func nonFileURLsAreSkipped() {
        #expect(store.add(files(URL(string: "https://example.com")!)) == 0)
        #expect(store.items.isEmpty)
    }

    @Test func keepsAtMostMaxItemsAndReportsOverflow() {
        var removed: [ShelfItem] = []
        store.onRemove = { removed += $0 }
        let urls = (0..<(ShelfStore.maxItems + 5)).map { URL(fileURLWithPath: "/tmp/\($0)") }
        store.add(Array(urls.prefix(10)).map { DroppedFile(url: $0, isOwned: false) })
        store.add(Array(urls.dropFirst(10)).map { DroppedFile(url: $0, isOwned: false) })
        #expect(store.items.count == ShelfStore.maxItems)
        // The oldest drop is the one cut off.
        #expect(store.items.first?.url == urls[10])
        #expect(removed.map(\.url) == Array(urls[5..<10]))
    }

    @Test func removeAndRemoveAllReportRemovedItems() {
        var removed: [ShelfItem] = []
        store.onRemove = { removed += $0 }
        store.add(files(a, b))
        store.remove(store.items[0].id)
        #expect(store.items.map(\.url) == [b])
        store.removeAll()
        #expect(store.items.isEmpty)
        #expect(removed.map(\.url) == [a, b])
    }

    @Test func removeMissingDropsVanishedFiles() {
        store.add(files(a, b, c))
        store.removeMissing { $0 != b }
        #expect(store.items.map(\.url) == [a, c])
    }

    @Test func expiryUsesAddedDate() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.add(files(a), now: start)
        store.add(files(b), now: start.addingTimeInterval(30))
        #expect(store.nextExpiry(lifetime: 60) == start.addingTimeInterval(60))
        #expect(store.nextExpiry(lifetime: nil) == nil)

        store.removeExpired(lifetime: 60, now: start.addingTimeInterval(59))
        #expect(store.items.count == 2)
        store.removeExpired(lifetime: 60, now: start.addingTimeInterval(60))
        #expect(store.items.map(\.url) == [b])
        store.removeExpired(lifetime: nil, now: .distantFuture)
        #expect(store.items.map(\.url) == [b])
    }
}

@MainActor
struct ShelfPersistenceTests {
    let directory: URL
    let persistence: ShelfPersistence

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("thenotch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        persistence = ShelfPersistence(fileURL: directory.appendingPathComponent("Shelf.json"))
    }

    func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    @Test func itemsSurviveARelaunch() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let b = try makeFile("b.png")
        let store = ShelfStore(persistence: persistence)
        store.add([DroppedFile(url: a, isOwned: false), DroppedFile(url: b, isOwned: true)])

        let reloaded = ShelfStore(persistence: persistence).items
        #expect(reloaded.map(\.id) == store.items.map(\.id))
        #expect(reloaded.map(\.isOwned) == [false, true])
        #expect(reloaded.map(\.url.standardizedFileURL.path) == [a, b].map(\.standardizedFileURL.path))
        #expect(reloaded.map(\.addedAt.timeIntervalSince1970) == store.items.map(\.addedAt.timeIntervalSince1970))
    }

    @Test func bookmarksFollowAMovedFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        ShelfStore(persistence: persistence).add([DroppedFile(url: a, isOwned: false)])

        let moved = directory.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: a, to: moved)
        #expect(ShelfStore(persistence: persistence).items.first?.name == "renamed.txt")
    }

    @Test func deletedFilesAreDroppedOnLoad() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        ShelfStore(persistence: persistence).add([DroppedFile(url: a, isOwned: false), DroppedFile(url: b, isOwned: false)])

        try FileManager.default.removeItem(at: a)
        #expect(ShelfStore(persistence: persistence).items.map(\.name) == ["b.txt"])
    }

    @Test func missingOrCorruptFileLoadsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(persistence.load().isEmpty)
        try Data("nope".utf8).write(to: persistence.fileURL)
        #expect(persistence.load().isEmpty)
    }

    @Test func ownedFoldersAreOnlyDirectChildren() {
        let root = URL(fileURLWithPath: "/x/Dropped")
        #expect(ShelfModule.isFolder(URL(fileURLWithPath: "/x/Dropped/UUID"), directlyIn: root))
        #expect(!ShelfModule.isFolder(URL(fileURLWithPath: "/x/Dropped"), directlyIn: root))
        #expect(!ShelfModule.isFolder(URL(fileURLWithPath: "/Users/me/Desktop"), directlyIn: root))
    }
}

@MainActor
struct ShelfDragTests {
    @Test func movedOrTrashedFilesLeaveTheShelf() {
        #expect(ShelfDrag.fileLeft(after: .move))
        #expect(ShelfDrag.fileLeft(after: .delete))
        #expect(ShelfDrag.fileLeft(after: [.move, .generic]))
    }

    @Test func copiedOrCancelledFilesStay() {
        #expect(!ShelfDrag.fileLeft(after: .copy))
        #expect(!ShelfDrag.fileLeft(after: .generic))
        #expect(!ShelfDrag.fileLeft(after: []))
    }
}
