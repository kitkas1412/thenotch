//
//  FileDragTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct FileDragTests {
    @Test func newDragWithFilesIsAFileDrag() {
        #expect(FileDrag.isFileDrag(changeCount: 8, changeCountAtMouseDown: 7, hasFileURLs: true))
    }

    @Test func staleFilesFromAPreviousDragAreIgnored() {
        // Moving a window: the pasteboard still holds the last drag's files.
        #expect(!FileDrag.isFileDrag(changeCount: 7, changeCountAtMouseDown: 7, hasFileURLs: true))
    }

    @Test func newDragWithoutFilesIsIgnored() {
        #expect(!FileDrag.isFileDrag(changeCount: 8, changeCountAtMouseDown: 7, hasFileURLs: false))
    }

    @Test func loadsFileURLsFromItemProviders() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("thenotch-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let providers = [NSItemProvider(object: file as NSURL), NSItemProvider(object: "not a file" as NSString)]
        let urls = await FileDrop.loadFileURLs(from: providers)
        #expect(urls.map(\.standardizedFileURL) == [file.standardizedFileURL])
    }
}
