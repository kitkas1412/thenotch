//
//  ClipboardHistoryTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct ClipboardHistoryTests {
    typealias F = ClipboardFixtures

    @Test func insertPutsNewestOnTop() {
        var history = ClipboardHistory(limit: 10)
        history.insert(F.textItem("a"))
        history.insert(F.textItem("b"))
        #expect(history.items.map(\.contentHash) == [ClipboardItem.hash(text: "b"), ClipboardItem.hash(text: "a")])
    }

    @Test func duplicateMovesExistingToTopKeepsItsIDAndReturnsDuplicateBlob() {
        var history = ClipboardHistory(limit: 10)
        let first = F.imageItem(bytes: 10, tag: "same", at: 1)
        history.insert(first)
        history.insert(F.textItem("other", at: 2))
        let duplicate = F.imageItem(bytes: 10, tag: "same", at: 5)
        let freed = history.insert(duplicate)
        #expect(history.items.count == 2)
        #expect(history.items[0].id == first.id)
        #expect(history.items[0].lastUsedAt == Date(timeIntervalSince1970: 5))
        #expect(history.entry(for: duplicate)?.id == first.id)
        // The first's blob stays referenced; the duplicate's blob was never in the history, so nothing is "freed".
        #expect(freed.isEmpty)
        #expect(history.items.compactMap(\.blobID) == [first.blobID!])
    }

    @Test func duplicateDoesNotMoveLastUsedBackwards() {
        var history = ClipboardHistory(limit: 10)
        history.insert(F.textItem("a", at: 10))
        history.insert(F.textItem("a", at: 3))
        #expect(history.items[0].lastUsedAt == Date(timeIntervalSince1970: 10))
    }

    @Test func limitEvictsOldestAndReturnsTheirBlobs() {
        var history = ClipboardHistory(limit: 2)
        let oldest = F.imageItem(bytes: 1, at: 1)
        history.insert(oldest)
        history.insert(F.textItem("b"))
        let freed = history.insert(F.textItem("c"))
        #expect(freed == [oldest.blobID!])
        #expect(history.items.count == 2)
        #expect(history.items.map(\.contentHash) == [ClipboardItem.hash(text: "c"), ClipboardItem.hash(text: "b")])
    }

    @Test func evictToLimitDropsOldestAndSetsLimit() {
        var history = ClipboardHistory(limit: 5)
        let a = F.imageItem(bytes: 1), b = F.imageItem(bytes: 1), c = F.imageItem(bytes: 1)
        for item in [a, b, c] { history.insert(item) }
        let freed = history.evict(toLimit: 1)
        #expect(history.limit == 1)
        #expect(history.items.map(\.id) == [c.id])
        #expect(Set(freed) == [a.blobID!, b.blobID!])
        #expect(freed == freed.sorted { $0.uuidString < $1.uuidString })
    }

    @Test func limitIsAtLeastOne() {
        var history = ClipboardHistory(limit: 0)
        #expect(history.limit == 1)
        history.insert(F.textItem("a"))
        history.insert(F.textItem("b"))
        #expect(history.items.count == 1)
        history.evict(toLimit: -5)
        #expect(history.limit == 1)
    }

    @Test func imageByteCapDropsOldestImagesButKeepsText() {
        var history = ClipboardHistory(limit: 100)
        let half = ClipboardHistory.maxImageBytes / 2
        let old = F.imageItem(bytes: half, at: 1)
        history.insert(old)
        history.insert(F.textItem("keep"))
        history.insert(F.imageItem(bytes: half, at: 3))
        // Exactly at the cap: nothing dropped.
        #expect(history.items.count == 3)
        let big = F.imageItem(bytes: 1, at: 4)
        let freed = history.insert(big)
        #expect(freed == [old.blobID!])
        #expect(history.items.count == 3)
        #expect(history.imageBytes <= ClipboardHistory.maxImageBytes)
        #expect(history.items.contains { $0.contentHash == ClipboardItem.hash(text: "keep") })
    }

    @Test func markUsedMovesToTopAndSetsTime() {
        var history = ClipboardHistory(limit: 10)
        let a = F.textItem("a", at: 1)
        history.insert(a)
        history.insert(F.textItem("b", at: 2))
        let now = Date(timeIntervalSince1970: 99)
        history.markUsed(a.id, now: now)
        #expect(history.items[0].id == a.id)
        #expect(history.items[0].lastUsedAt == now)
        history.markUsed(UUID(), now: now)
        #expect(history.items.count == 2)
    }

    @Test func removeAndClearReturnFreedBlobs() {
        var history = ClipboardHistory(limit: 10)
        let image = F.imageItem(bytes: 1)
        let text = F.textItem("t")
        history.insert(image)
        history.insert(text)
        #expect(history.remove(text.id).isEmpty)
        #expect(history.remove(UUID()).isEmpty)
        history.insert(text)
        #expect(history.remove(image.id) == [image.blobID!])
        history.insert(image)
        #expect(history.clear() == [image.blobID!])
        #expect(history.items.isEmpty)
    }
}
