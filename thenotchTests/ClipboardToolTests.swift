//
//  ClipboardToolTests.swift
//  thenotchTests
//
//  Start-up safety net for "clear on quit" and stop(), with an in-memory
//  key and a temporary directory (never the Keychain).
//

import AppKit
import CryptoKit
import Foundation
import Testing
@testable import thenotch

@MainActor
struct ClipboardToolTests {
    typealias F = ClipboardFixtures

    let directory = F.tempDirectory()
    let persistence: ClipboardPersistence
    let keys: InMemoryKeyStore
    let key = SymmetricKey(size: .bits256)
    let settings: AppSettings
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))

    init() {
        persistence = ClipboardPersistence(directory: directory)
        keys = InMemoryKeyStore(key: key)
        let suite = "thenotchTests.ClipboardTool.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
    }

    func makeTool() -> ClipboardTool {
        ClipboardTool(
            settings: settings, hotKeys: HotKeyCenter(), contributions: IslandContributions(),
            persistence: persistence, keyProvider: keys, pasteboard: pasteboard)
    }

    func cleanUp() {
        pasteboard.releaseGlobally()
        persistence.waitForPendingWrites()
        try? FileManager.default.removeItem(at: directory)
    }

    func data(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// A history saved by an earlier run.
    func seed(_ text: String) async {
        let store = ClipboardStore(persistence: persistence, keyProvider: keys, limit: 10)
        await store.load()
        store.add(F.textDraft(text))
        store.saveNow()
        persistence.waitForPendingWrites()
    }

    func reopen() async -> ClipboardStore {
        let store = ClipboardStore(persistence: persistence, keyProvider: keys, limit: 10)
        await store.load()
        return store
    }

    @Test func startClearsLeftoverHistoryWhenClearingOnQuit() async throws {
        defer { cleanUp() }
        await seed("left over")
        settings.clipboardClearOnQuit = true
        let tool = makeTool()
        tool.start()
        defer { tool.stop() }

        // The key is replaced as the last step of the start-up clear.
        #expect(await waitUntil { keys.currentKey.map(data) != data(key) })
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(tool.store.items.isEmpty)
        #expect(await waitUntil { tool.store.isPersistent })
    }

    @Test func startKeepsAndLoadsHistoryWhenNotClearingOnQuit() async throws {
        defer { cleanUp() }
        await seed("kept")
        settings.clipboardClearOnQuit = false
        let tool = makeTool()
        tool.start()
        defer { tool.stop() }

        #expect(await waitUntil { tool.store.isLoaded })
        #expect(tool.store.items.map(\.contentHash) == [ClipboardItem.hash(text: "kept")])
        #expect(FileManager.default.fileExists(atPath: persistence.indexURL.path))
        #expect(keys.currentKey.map(data) == data(key))
    }

    @Test func stopClearsFilesAndKeyWhenClearingOnQuit() async throws {
        defer { cleanUp() }
        await seed("left over")
        settings.clipboardClearOnQuit = true
        let tool = makeTool()
        tool.start()
        // Past the start-up clear, so nothing else is in flight.
        #expect(await waitUntil { keys.currentKey.map(data) != data(key) && tool.store.isPersistent })
        tool.store.add(F.textDraft("fresh"))
        tool.store.saveNow()
        persistence.waitForPendingWrites()
        #expect(FileManager.default.fileExists(atPath: persistence.indexURL.path))

        tool.stop()
        await persistence.runInBackground {}
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(keys.currentKey == nil)
        #expect(tool.store.items.isEmpty)
    }

    @Test func stopSavesHistoryWhenNotClearingOnQuit() async throws {
        defer { cleanUp() }
        settings.clipboardClearOnQuit = false
        let tool = makeTool()
        tool.start()
        #expect(await waitUntil { tool.store.isPersistent })
        tool.store.add(F.textDraft("saved"))
        tool.stop()
        persistence.waitForPendingWrites()

        #expect(tool.store.items.isEmpty) // memory dropped, files stay
        let next = await reopen()
        #expect(next.lastStorageIssue == nil)
        #expect(next.items.map(\.contentHash) == [ClipboardItem.hash(text: "saved")])
    }
}
