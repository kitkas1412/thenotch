//
//  ClipboardStoreTests.swift
//  thenotchTests
//

import CryptoKit
import Foundation
import Testing
@testable import thenotch

@MainActor
struct ClipboardStoreTests {
    typealias F = ClipboardFixtures

    let directory: URL
    let keys: InMemoryKeyStore
    let key: SymmetricKey
    let persistence: ClipboardPersistence

    init() {
        directory = F.tempDirectory()
        persistence = ClipboardPersistence(directory: directory)
        key = SymmetricKey(size: .bits256)
        keys = InMemoryKeyStore(key: key)
    }

    func makeStore(limit: Int = 10) -> ClipboardStore {
        ClipboardStore(persistence: persistence, keyProvider: keys, limit: limit)
    }

    func cleanUp() {
        persistence.waitForPendingWrites()
        try? FileManager.default.removeItem(at: directory)
    }

    func data(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    @Test func addsDedupesAndLimitsAfterLoad() async {
        defer { cleanUp() }
        let store = makeStore(limit: 2)
        await store.load()
        #expect(store.isLoaded && store.isPersistent)
        store.add(F.textDraft("a"))
        store.add(F.textDraft("b"))
        store.add(F.textDraft("a"))
        #expect(store.items.count == 2)
        #expect(store.items.map(\.contentHash) == [ClipboardItem.hash(text: "a"), ClipboardItem.hash(text: "b")])
        store.add(F.textDraft("c"))
        #expect(store.items.count == 2)
        #expect(!store.items.contains { $0.contentHash == ClipboardItem.hash(text: "b") })
        store.setLimit(1)
        #expect(store.limit == 1 && store.items.count == 1)
    }

    @Test func savedHistoryAndImagesSurviveANewStore() async throws {
        defer { cleanUp() }
        let store = makeStore()
        await store.load()
        store.add(F.textDraft("kept"))
        let imageID = try #require(store.add(F.imageDraft()))
        store.saveNow()
        let image = try #require(store.items.first { $0.id == imageID })
        #expect(await store.imageData(for: image) == F.png)

        let again = makeStore()
        await again.load()
        #expect(again.items.map(\.id) == store.items.map(\.id))
        #expect(await again.imageData(for: again.items[0]) == F.png)
        #expect(again.lastStorageIssue == nil)
    }

    @Test func nothingIsWrittenBeforeLoadFinishes() async {
        defer { cleanUp() }
        let store = makeStore()
        store.add(F.textDraft("early"))
        store.add(F.imageDraft())
        store.saveNow()
        persistence.waitForPendingWrites()
        #expect(!store.isLoaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        // After loading, the early entries are kept and the image is written.
        await store.load()
        #expect(store.items.count == 2)
        persistence.waitForPendingWrites()
        let blobs = try? FileManager.default.contentsOfDirectory(atPath: persistence.imagesDirectory.path)
        #expect(blobs?.count == 1)
    }

    @Test func transientKeyFailureKeepsFilesThenRetryMerges() async throws {
        defer { cleanUp() }
        let first = makeStore()
        await first.load()
        first.add(F.textDraft("saved"))
        first.saveNow()
        persistence.waitForPendingWrites()
        let before = try Data(contentsOf: persistence.indexURL)

        keys.failure = .keychain(-25308)
        let store = makeStore()
        store.add(F.textDraft("meanwhile"))
        await store.load()
        #expect(store.lastStorageIssue == .keyUnavailable)
        #expect(!store.isPersistent)
        #expect(try Data(contentsOf: persistence.indexURL) == before)
        #expect(keys.currentKey != nil)
        store.saveNow()
        #expect(try Data(contentsOf: persistence.indexURL) == before)

        keys.failure = nil
        await store.load()
        #expect(store.lastStorageIssue == nil)
        #expect(store.isPersistent)
        #expect(store.items.map(\.contentHash) == [ClipboardItem.hash(text: "meanwhile"), ClipboardItem.hash(text: "saved")])
    }

    @Test func invalidKeyDataWipesAndStartsFresh() async throws {
        defer { cleanUp() }
        let first = makeStore()
        await first.load()
        first.add(F.textDraft("old"))
        first.saveNow()
        persistence.waitForPendingWrites()

        keys.readFailure = .invalidKeyData
        let store = makeStore()
        await store.load()
        #expect(store.lastStorageIssue == .startedFresh)
        #expect(store.items.isEmpty)
        #expect(store.isPersistent)
        #expect(data(try #require(keys.currentKey)) != data(key))
        persistence.waitForPendingWrites()
        #expect(!FileManager.default.fileExists(atPath: persistence.indexURL.path))
    }

    @Test func invalidKeyDataThatCannotBeReplacedIsUnavailable() async {
        defer { cleanUp() }
        keys.readFailure = .invalidKeyData
        keys.failure = .keychain(-1)
        let store = makeStore()
        await store.load()
        #expect(store.lastStorageIssue == .keyUnavailable)
        #expect(!store.isPersistent)
    }

    @Test func indexThatWontOpenWipesAndStartsFresh() async {
        defer { cleanUp() }
        let other = SymmetricKey(size: .bits256)
        persistence.saveIndex([F.textItem("x")], key: other)
        persistence.waitForPendingWrites()
        let store = makeStore()
        await store.load()
        #expect(store.lastStorageIssue == .startedFresh)
        #expect(store.items.isEmpty)
        #expect(store.isPersistent)
        #expect(data(keys.currentKey!) == data(key))
        persistence.waitForPendingWrites()
        #expect(!FileManager.default.fileExists(atPath: persistence.indexURL.path))
    }

    @Test func clearRemovesFilesAndRotatesKey() async throws {
        defer { cleanUp() }
        let store = makeStore()
        await store.load()
        store.add(F.textDraft("a"))
        store.add(F.imageDraft())
        store.saveNow()
        persistence.waitForPendingWrites()
        #expect(FileManager.default.fileExists(atPath: persistence.indexURL.path))

        await store.clear()?.value
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(data(try #require(keys.currentKey)) != data(key))
        #expect(store.isPersistent)
        #expect(store.lastStorageIssue == nil)
    }

    @Test func addsDuringClearWaitForTheNewKey() async throws {
        defer { cleanUp() }
        let store = makeStore()
        await store.load()
        store.add(F.textDraft("old"))
        store.saveNow()
        let clearing = store.clear()
        // No key until the new one is there: kept in memory.
        #expect(!store.isPersistent)
        let imageID = try #require(store.add(F.imageDraft()))
        await clearing?.value
        #expect(store.isPersistent)
        store.saveNow()
        let again = makeStore()
        await again.load()
        #expect(again.items.map(\.id) == [imageID])
        #expect(await again.imageData(for: again.items[0]) == F.png)
        #expect(again.lastStorageIssue == nil)
    }

    @Test func clearWhoseKeyCantBeReplacedSaysSo() async {
        defer { cleanUp() }
        let store = makeStore()
        await store.load()
        store.add(F.textDraft("a"))
        store.saveNow()
        keys.failure = .keychain(-1)
        await store.clear()?.value
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(store.lastStorageIssue == .keyUnavailable)
        #expect(!store.isPersistent)
    }

    @Test func clearNowDeletesFilesAndKeyBeforeReturning() async {
        defer { cleanUp() }
        let store = makeStore()
        await store.load()
        store.add(F.textDraft("a"))
        store.add(F.imageDraft())
        // Writes still queued, and one pending save.
        store.clearNow()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(keys.currentKey == nil)
        #expect(store.items.isEmpty)
        // The next start finds nothing to complain about.
        let next = makeStore()
        await next.load()
        #expect(next.lastStorageIssue == nil)
        #expect(next.items.isEmpty)
    }

    @Test func hasSavedFilesOnlyWhenSomethingIsOnDisk() async {
        defer { cleanUp() }
        let store = makeStore()
        #expect(await !store.hasSavedFiles())
        await store.load()
        store.add(F.textDraft("a"))
        store.saveNow()
        #expect(await store.hasSavedFiles())
    }

    @Test func discardedStoreIgnoresALoadUnderWay() async {
        defer { cleanUp() }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        keys.onKey = {
            entered.signal()
            release.wait()
        }
        let store = makeStore()
        store.add(F.textDraft("early"))
        store.add(F.imageDraft())
        let loading = Task { await store.load() }
        await Task.detached { entered.wait() }.value
        store.discard()
        release.signal()
        await loading.value
        keys.onKey = nil

        #expect(!store.isLoaded)
        #expect(!store.isPersistent)
        #expect(store.add(F.textDraft("later")) == nil)
        #expect(store.clear() == nil)
        store.saveNow()
        persistence.waitForPendingWrites()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func removeAndMarkUsedChangeOrder() async throws {
        defer { cleanUp() }
        let store = makeStore()
        await store.load()
        let a = try #require(store.add(F.textDraft("a"), now: Date(timeIntervalSince1970: 1)))
        let b = try #require(store.add(F.textDraft("b"), now: Date(timeIntervalSince1970: 2)))
        store.markUsed(a, now: Date(timeIntervalSince1970: 3))
        #expect(store.items.map(\.id) == [a, b])
        store.remove(a)
        #expect(store.items.map(\.id) == [b])
    }

    @Test func clearThatLeavesFilesAndNoKeySaysBoth() async throws {
        // The history inside a parent that can't be written: its files
        // can't be deleted.
        let parent = F.tempDirectory()
        let locked = ClipboardPersistence(directory: parent.appendingPathComponent("Clipboard", isDirectory: true))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        let store = ClipboardStore(persistence: locked, keyProvider: keys, limit: 10)
        await store.load()
        store.add(F.textDraft("a"))
        store.saveNow()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)

        keys.failure = .keychain(-1)
        await store.clear()?.value
        #expect(FileManager.default.fileExists(atPath: locked.directory.path))
        #expect(store.lastStorageIssue == .notDeletedKeyUnavailable)
        #expect(!store.isPersistent)

        // Key back, files still stuck: only that is left to say.
        keys.failure = nil
        await store.clear()?.value
        #expect(store.lastStorageIssue == .notDeleted)

        // Both fixed.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        await store.clear()?.value
        #expect(store.lastStorageIssue == nil)
        #expect(!FileManager.default.fileExists(atPath: locked.directory.path))
    }

    @Test func thumbnailCacheClearBumpsGeneration() {
        let thumbnails = ClipboardThumbnails()
        let before = thumbnails.generation
        thumbnails.removeAll()
        #expect(thumbnails.generation == before + 1)
    }
}
