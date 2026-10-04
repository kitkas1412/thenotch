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

    /// A store with the saved shelf read, as after launch.
    func loadedStore() async -> ShelfStore {
        let store = ShelfStore(persistence: persistence)
        await store.load()
        return store
    }

    @Test func itemsSurviveARelaunch() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let b = try makeFile("b.png")
        let store = await loadedStore()
        store.add([DroppedFile(url: a, isOwned: false), DroppedFile(url: b, isOwned: true)])
        store.saveNow()

        let reloaded = await loadedStore().items
        #expect(reloaded.map(\.id) == store.items.map(\.id))
        #expect(reloaded.map(\.isOwned) == [false, true])
        #expect(reloaded.map(\.url.standardizedFileURL.path) == [a, b].map(\.standardizedFileURL.path))
        #expect(reloaded.map(\.addedAt.timeIntervalSince1970) == store.items.map(\.addedAt.timeIntervalSince1970))
    }

    @Test func bookmarksFollowAMovedFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let store = await loadedStore()
        store.add([DroppedFile(url: a, isOwned: false)])
        store.saveNow()

        let moved = directory.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: a, to: moved)
        #expect(await loadedStore().items.first?.name == "renamed.txt")
    }

    @Test func deletedFilesAreDroppedOnLoad() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        let store = await loadedStore()
        store.add([DroppedFile(url: a, isOwned: false), DroppedFile(url: b, isOwned: false)])
        store.saveNow()

        try FileManager.default.removeItem(at: a)
        #expect(await loadedStore().items.map(\.name) == ["b.txt"])
    }

    @Test func changesAreSavedAfterADelay() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let store = await loadedStore()
        store.add([DroppedFile(url: a, isOwned: false)])
        #expect(persistence.load().isEmpty)

        // Written in the background once the delay has passed.
        var saved: [ShelfItem] = []
        let deadline = ContinuousClock.now + ShelfStore.saveDelay + .seconds(3)
        while saved.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            saved = persistence.load()
        }
        #expect(saved.map(\.id) == store.items.map(\.id))
    }

    @Test func saveNowWithoutChangesKeepsTheFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let first = await loadedStore()
        first.add([DroppedFile(url: a, isOwned: false)])
        first.saveNow()

        // Loading isn't a change: nothing is pending, nothing is rewritten.
        await loadedStore().saveNow()
        #expect(persistence.load().count == 1)
    }

    @Test func nothingIsSavedBeforeLoading() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        let first = await loadedStore()
        first.add([DroppedFile(url: a, isOwned: false)])
        first.saveNow()

        // A file dropped while the saved shelf is still being read.
        let store = ShelfStore(persistence: persistence)
        store.add([DroppedFile(url: b, isOwned: false)])
        store.saveNow()
        #expect(persistence.load().map(\.name) == ["a.txt"])

        await store.load()
        #expect(store.items.map(\.name) == ["b.txt", "a.txt"])
        store.saveNow()
        #expect(persistence.load().map(\.name) == ["b.txt", "a.txt"])
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
    @Test func movedOrTrashedFilesLeftTheirPlace() {
        #expect(ShelfDrag.outcome(of: .move) == .moved)
        #expect(ShelfDrag.outcome(of: .delete) == .moved)
        #expect(ShelfDrag.outcome(of: [.move, .generic]) == .moved)
    }

    @Test func filesTakenByAnAppAreCopies() {
        #expect(ShelfDrag.outcome(of: .copy) == .copied)
        #expect(ShelfDrag.outcome(of: .generic) == .copied)
        #expect(ShelfDrag.outcome(of: .link) == .copied)
    }

    @Test func cancelledDragsChangeNothing() {
        #expect(ShelfDrag.outcome(of: []) == .none)
    }
}
