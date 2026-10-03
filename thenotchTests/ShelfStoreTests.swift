//
//  ShelfStoreTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

@MainActor
struct ShelfStoreTests {
    let store = ShelfStore()
    let a = URL(fileURLWithPath: "/tmp/a.txt")
    let b = URL(fileURLWithPath: "/tmp/b.png")
    let c = URL(fileURLWithPath: "/tmp/c.pdf")

    @Test func newestDropComesFirstInDropOrder() {
        store.add([a])
        store.add([b, c])
        #expect(store.items.map(\.url) == [b, c, a])
    }

    @Test func duplicatesAreSkipped() {
        store.add([a, b])
        let added = store.add([URL(fileURLWithPath: "/tmp/./a.txt"), c, c])
        #expect(added == 1)
        #expect(store.items.map(\.url) == [c, a, b])
    }

    @Test func nonFileURLsAreSkipped() {
        #expect(store.add([URL(string: "https://example.com")!]) == 0)
        #expect(store.items.isEmpty)
    }

    @Test func keepsAtMostMaxItems() {
        let urls = (0..<(ShelfStore.maxItems + 5)).map { URL(fileURLWithPath: "/tmp/\($0)") }
        store.add(Array(urls.prefix(10)))
        store.add(Array(urls.dropFirst(10)))
        #expect(store.items.count == ShelfStore.maxItems)
        // The oldest drop is the one cut off.
        #expect(store.items.first?.url == urls[10])
        #expect(!store.items.contains { $0.url == urls[9] })
    }

    @Test func removeAndRemoveAll() {
        store.add([a, b])
        store.remove(store.items[0].id)
        #expect(store.items.map(\.url) == [b])
        store.removeAll()
        #expect(store.items.isEmpty)
    }

    @Test func removeMissingDropsVanishedFiles() {
        store.add([a, b, c])
        store.removeMissing { $0 != b }
        #expect(store.items.map(\.url) == [a, c])
    }
}
