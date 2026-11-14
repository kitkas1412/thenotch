//
//  ClipboardPersistenceTests.swift
//  thenotchTests
//

import CryptoKit
import Foundation
import Testing
@testable import thenotch

struct ClipboardPersistenceTests {
    typealias F = ClipboardFixtures

    let directory: URL
    let key = SymmetricKey(size: .bits256)
    /// One instance per test: each has its own serial queue.
    let persistence: ClipboardPersistence

    init() {
        directory = F.tempDirectory()
        persistence = ClipboardPersistence(directory: directory)
    }

    func cleanUp() {
        persistence.waitForPendingWrites()
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func roundTripsIndexAndBlobWithPermissions() throws {
        defer { cleanUp() }
        let blobID = UUID()
        let image = F.imageItem(bytes: 3, blobID: blobID)
        let text = F.textItem("hello")
        persistence.writeBlob(blobID, bytes: Data([1, 2, 3]), key: key)
        persistence.saveIndex([text, image], key: key)
        persistence.waitForPendingWrites()

        #expect(try persistence.readBlob(blobID, key: key) == Data([1, 2, 3]))
        let result = persistence.load(key: key)
        #expect(result.outcome == .loaded)
        #expect(result.items == [text, image])
        #expect(result.droppedItems == 0)
        #expect(result.removedOrphans == 0)

        #expect(F.permissions(directory) == 0o700)
        #expect(F.permissions(persistence.imagesDirectory) == 0o700)
        #expect(F.permissions(persistence.indexURL) == 0o600)
        #expect(F.permissions(persistence.blobURL(blobID)) == 0o600)
        // Nothing readable on disk.
        let raw = try Data(contentsOf: persistence.indexURL)
        #expect(raw.range(of: Data("hello".utf8)) == nil)
    }

    @Test func loadWithoutFilesIsNoHistory() {
        defer { cleanUp() }
        let result = persistence.load(key: key)
        #expect(result.outcome == .noHistory)
        #expect(result.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func orphanBlobIsRemovedOnLoad() throws {
        defer { cleanUp() }
        let kept = UUID(), orphan = UUID()
        persistence.writeBlob(kept, bytes: Data([1]), key: key)
        persistence.writeBlob(orphan, bytes: Data([2]), key: key)
        persistence.saveIndex([F.imageItem(bytes: 1, blobID: kept)], key: key)
        let result = persistence.load(key: key)
        #expect(result.outcome == .loaded)
        #expect(result.items.count == 1)
        #expect(result.removedOrphans == 1)
        #expect(FileManager.default.fileExists(atPath: persistence.blobURL(kept).path))
        #expect(!FileManager.default.fileExists(atPath: persistence.blobURL(orphan).path))
    }

    @Test func entryWithMissingBlobIsDropped() {
        defer { cleanUp() }
        persistence.saveIndex([F.imageItem(bytes: 1), F.textItem("t")], key: key)
        let result = persistence.load(key: key)
        #expect(result.items.count == 1)
        #expect(result.droppedItems == 1)
    }

    @Test func wrongKeyWipesEverything() {
        defer { cleanUp() }
        let blobID = UUID()
        persistence.writeBlob(blobID, bytes: Data([1]), key: key)
        persistence.saveIndex([F.imageItem(bytes: 1, blobID: blobID)], key: key)
        let result = persistence.load(key: SymmetricKey(size: .bits256))
        #expect(result.outcome == .unreadableWiped)
        #expect(result.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func blobSwappedBetweenIDsCannotBeRead() throws {
        defer { cleanUp() }
        let a = UUID(), b = UUID()
        persistence.writeBlob(a, bytes: Data([1]), key: key)
        persistence.waitForPendingWrites()
        try FileManager.default.copyItem(at: persistence.blobURL(a), to: persistence.blobURL(b))
        #expect(throws: ClipboardCrypto.Error.authenticationFailed) {
            try persistence.readBlob(b, key: key)
        }
    }

    @Test func deleteBlobsAndWipe() throws {
        defer { cleanUp() }
        let id = UUID()
        persistence.writeBlob(id, bytes: Data([1]), key: key)
        persistence.saveIndex([], key: key)
        persistence.waitForPendingWrites()
        persistence.deleteBlobs([id])
        persistence.waitForPendingWrites()
        #expect(!FileManager.default.fileExists(atPath: persistence.blobURL(id).path))
        persistence.wipe()
        persistence.waitForPendingWrites()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func wipeNowReturnsOnceEverythingQueuedIsDeleted() {
        defer { cleanUp() }
        let id = UUID()
        // Queued, not yet waited for.
        persistence.writeBlob(id, bytes: Data([1]), key: key)
        persistence.saveIndex([F.imageItem(bytes: 1, blobID: id)], key: key)
        #expect(persistence.wipeNow())
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        // Nothing to delete is fine.
        #expect(persistence.wipeNow())
    }

    @Test func wipeInBackgroundRunsTheKeyActionAfterTheWipe() async {
        defer { cleanUp() }
        persistence.saveIndex([F.textItem("a")], key: key)
        let directory = directory
        let result = await persistence.wipeInBackground {
            // Off the test's task: report through the error.
            let wiped = !FileManager.default.fileExists(atPath: directory.path)
            throw ClipboardKeyError.keychain(wiped ? -25300 : 1)
        }
        #expect(result.filesRemoved)
        #expect(result.key == nil)
        #expect(result.keyError == .keychain(-25300))
        #expect(await !persistence.hasFilesInBackground())
    }

    @Test func copiesShareTheQueue() {
        defer { cleanUp() }
        let copy = persistence
        copy.saveIndex([F.textItem("a")], key: key)
        // Waiting on the original waits for the copy's write.
        persistence.waitForPendingWrites()
        #expect(FileManager.default.fileExists(atPath: persistence.indexURL.path))
    }

    @Test func directoryIsExcludedFromBackup() throws {
        defer { cleanUp() }
        persistence.saveIndex([], key: key)
        persistence.waitForPendingWrites()
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func symlinkedDirectoriesAreReplacedNotFollowed() throws {
        defer { cleanUp() }
        let elsewhere = F.tempDirectory()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let bystander = elsewhere.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: bystander)

        // The images directory points elsewhere: loading must not clean it
        // up as orphans, and writing must not go there.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: persistence.imagesDirectory, withDestinationURL: elsewhere)
        _ = persistence.load(key: key)
        #expect(FileManager.default.fileExists(atPath: bystander.path))
        let id = UUID()
        persistence.writeBlob(id, bytes: Data([1]), key: key)
        persistence.waitForPendingWrites()
        let attributes = try FileManager.default.attributesOfItem(atPath: persistence.imagesDirectory.path)
        #expect(attributes[.type] as? FileAttributeType == .typeDirectory)
        #expect(try persistence.readBlob(id, key: key) == Data([1]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path) == ["keep.txt"])

        // The main directory as a symlink: replaced, the target untouched.
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: elsewhere)
        persistence.saveIndex([], key: key)
        persistence.waitForPendingWrites()
        let main = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect(main[.type] as? FileAttributeType == .typeDirectory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path) == ["keep.txt"])
        // Wiping a symlink removes the link only.
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: elsewhere)
        #expect(persistence.wipeNow())
        #expect(FileManager.default.fileExists(atPath: bystander.path))
    }
}
