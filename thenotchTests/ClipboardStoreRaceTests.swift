//
//  ClipboardStoreRaceTests.swift
//  thenotchTests
//
//  Key-handling races between load(), clear() and clearNow().
//

import CryptoKit
import Foundation
import Testing
@testable import thenotch

@MainActor
struct ClipboardStoreRaceTests {
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

    func makeStore() -> ClipboardStore {
        ClipboardStore(persistence: persistence, keyProvider: keys, limit: 10)
    }

    func cleanUp() {
        keys.onKey = nil
        persistence.waitForPendingWrites()
        try? FileManager.default.removeItem(at: directory)
    }

    func data(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// A saved history made with the provider's current key.
    func seed(_ text: String) async {
        let store = makeStore()
        await store.load()
        store.add(F.textDraft(text))
        store.saveNow()
        persistence.waitForPendingWrites()
    }

    /// Saves an item with `store` and reads it back with a new store on the
    /// same provider and directory: proves the store's key is the provider's.
    func expectReopens(from store: ClipboardStore, text: String, alsoKept: [String] = []) async {
        store.add(F.textDraft(text))
        store.saveNow()
        persistence.waitForPendingWrites()
        let next = makeStore()
        await next.load()
        #expect(next.lastStorageIssue == nil)
        #expect(next.items.map(\.contentHash) == [ClipboardItem.hash(text: text)] + alsoKept)
        #expect(!next.items.contains { $0.contentHash == ClipboardItem.hash(text: "old") })
    }

    /// Holds the first `key()` call on the queue until `release()`.
    final class Gate: @unchecked Sendable {
        private let entered = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        func hook() { entered.signal(); released.wait() }
        func waitEntered() async { await Task.detached { [entered] in entered.wait() }.value }
        func release() { released.signal() }
    }

    @Test func loadDuringKeyReplacementDoesNotAdoptTheStaleKey() async throws {
        defer { cleanUp() }
        await seed("old")
        keys.readFailure = .keychain(-1)
        let store = makeStore()
        await store.load()
        #expect(store.lastStorageIssue == .keyUnavailable)
        #expect(!store.isPersistent)

        keys.readFailure = nil
        let replacing = try #require(store.clear())
        await store.load() // the replacement is pending: a no-op
        #expect(!store.isPersistent)

        await replacing.value
        #expect(store.isPersistent)
        let current = try #require(keys.currentKey)
        #expect(data(current) != data(key))
        // What the store seals opens with the provider's current key.
        let imageID = try #require(store.add(F.imageDraft()))
        let blobID = try #require(store.items.first { $0.id == imageID }?.blobID)
        persistence.waitForPendingWrites()
        #expect(try persistence.readBlob(blobID, key: current) == F.png)
        await expectReopens(from: store, text: "new", alsoKept: [ClipboardItem.hash(image: F.png)])
    }

    @Test func loadRightAfterClearIsANoOpAndTheKeyStaysConsistent() async throws {
        defer { cleanUp() }
        await seed("old")
        let store = makeStore()
        await store.load()
        // Synchronously: the rotation is already on the queue when clear() returns.
        let replacing = try #require(store.clear())
        await store.load()
        #expect(!store.isPersistent)
        await replacing.value
        #expect(store.isPersistent)
        #expect(data(try #require(keys.currentKey)) != data(key))
        await expectReopens(from: store, text: "new")
    }

    @Test func clearBeforeLoadThatCantDeleteReportsIt() async throws {
        let parent = F.tempDirectory()
        let locked = ClipboardPersistence(directory: parent.appendingPathComponent("Clipboard", isDirectory: true))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            locked.waitForPendingWrites()
            try? FileManager.default.removeItem(at: parent)
        }
        let saver = ClipboardStore(persistence: locked, keyProvider: keys, limit: 10)
        await saver.load()
        saver.add(F.textDraft("old"))
        saver.saveNow()
        locked.waitForPendingWrites()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)

        let store = ClipboardStore(persistence: locked, keyProvider: keys, limit: 10)
        store.clear() // not loaded yet: the wipe is queued
        #expect(await waitUntil { store.lastStorageIssue == .notDeleted })
    }

    @Test func clearDuringLoadDropsWhatWasRead() async throws {
        defer { cleanUp() }
        await seed("old")
        let gate = Gate()
        keys.onKey = gate.hook
        let store = makeStore()
        let loading = Task { await store.load() }
        await gate.waitEntered()
        store.add(F.textDraft("typed meanwhile"))
        store.clear()
        gate.release()
        await loading.value
        keys.onKey = nil

        #expect(store.isLoaded)
        #expect(store.items.isEmpty)
        #expect(await waitUntil { store.isPersistent })
        #expect(data(try #require(keys.currentKey)) != data(key))
        let next = makeStore()
        await next.load()
        #expect(next.items.isEmpty)
    }

    @Test func clearDuringFreshRotationLeavesOneConsistentKey() async throws {
        defer { cleanUp() }
        await seed("old")
        keys.readFailure = .invalidKeyData // load: delete + rotate (.fresh)
        let gate = Gate()
        keys.onKey = gate.hook
        let store = makeStore()
        let loading = Task { await store.load() }
        await gate.waitEntered()
        store.clear()
        gate.release()
        await loading.value
        keys.onKey = nil
        keys.readFailure = nil

        #expect(await waitUntil { store.isPersistent })
        let current = try #require(keys.currentKey)
        #expect(data(current) != data(key))
        #expect(!FileManager.default.fileExists(atPath: persistence.indexURL.path))
        await expectReopens(from: store, text: "after")
    }

    @Test func clearAfterFreshRotationLeavesOneConsistentKey() async throws {
        defer { cleanUp() }
        await seed("old")
        keys.readFailure = .invalidKeyData
        let store = makeStore()
        await store.load()
        #expect(store.lastStorageIssue == .startedFresh)
        keys.readFailure = nil
        let rotated = try #require(keys.currentKey)

        await store.clear()?.value
        #expect(data(try #require(keys.currentKey)) != data(rotated))
        #expect(store.isPersistent)
        await expectReopens(from: store, text: "after")
    }

    @Test func damagedIndexStartsFreshAndKeepsTheKey() async throws {
        defer { cleanUp() }
        await seed("old")
        try Data("garbage".utf8).write(to: persistence.indexURL)
        let store = makeStore()
        await store.load()
        #expect(store.lastStorageIssue == .startedFresh)
        #expect(store.isPersistent)
        #expect(data(try #require(keys.currentKey)) == data(key))
        await store.clear()?.value
        await expectReopens(from: store, text: "after")
    }

    @Test func clearNowDuringLoadLeavesNoKeyAndNothingLoaded() async throws {
        defer { cleanUp() }
        await seed("old")
        let gate = Gate()
        keys.onKey = gate.hook
        let store = makeStore()
        let loading = Task { await store.load() }
        await gate.waitEntered()
        // clearNow waits for the queue, which waits for the gate: open it
        // from another thread (before or after, the outcome is the same).
        Task.detached { gate.release() }
        store.clearNow()
        await loading.value
        keys.onKey = nil
        await persistence.runInBackground {} // nothing queued later may recreate the key

        #expect(keys.currentKey == nil)
        #expect(!store.isPersistent)
        #expect(!store.isLoaded)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        // Nothing is left for the next start to trip over.
        let next = makeStore()
        await next.load()
        #expect(next.lastStorageIssue == nil && next.items.isEmpty)
    }

    @Test func supersededClearsLeaveOnlyTheLastKey() async throws {
        defer { cleanUp() }
        await seed("old")
        let store = makeStore()
        await store.load()
        let first = try #require(store.clear())
        let second = try #require(store.clear())
        await first.value
        await second.value

        #expect(store.isPersistent)
        #expect(data(try #require(keys.currentKey)) != data(key))
        await expectReopens(from: store, text: "after")
    }
}
