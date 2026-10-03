//
//  FileDragTests.swift
//  thenotchTests
//

import Foundation
import UniformTypeIdentifiers
import Testing
@testable import thenotch

struct FileDragTests {
    @Test func newDragWithFilesIsAFileDrag() {
        #expect(FileDrag.isFileDrag(changeCount: 8, changeCountAtMouseDown: 7, carriesFiles: true))
    }

    @Test func staleFilesFromAPreviousDragAreIgnored() {
        // Moving a window: the pasteboard still holds the last drag's files.
        #expect(!FileDrag.isFileDrag(changeCount: 7, changeCountAtMouseDown: 7, carriesFiles: true))
    }

    @Test func newDragWithoutFilesIsIgnored() {
        #expect(!FileDrag.isFileDrag(changeCount: 8, changeCountAtMouseDown: 7, carriesFiles: false))
    }

    @Test func filesPromisesAndImagesCountAsFiles() {
        let promise = "com.apple.NSFilePromiseItemMetaData"
        #expect(FileDrag.carriesFiles(["public.file-url"], promiseTypes: [promise]))
        #expect(FileDrag.carriesFiles(["public.utf8-plain-text", promise], promiseTypes: [promise]))
        #expect(FileDrag.carriesFiles(["public.png"], promiseTypes: []))
        #expect(FileDrag.carriesFiles(["com.adobe.pdf"], promiseTypes: []))
    }

    @Test func textAndLinksDontCountAsFiles() {
        #expect(!FileDrag.carriesFiles(["public.utf8-plain-text", "public.url"], promiseTypes: ["com.apple.NSFilePromiseItemMetaData"]))
        #expect(!FileDrag.carriesFiles([], promiseTypes: []))
    }

    @Test func loadsFilesAndSavesContentFromItemProviders() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("thenotch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent("note.txt")
        try Data("hi".utf8).write(to: file)

        let image = NSItemProvider()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        image.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(png, nil)
            return nil
        }
        image.suggestedName = "photo"

        let providers = [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: "not a file" as NSString),
            image,
        ]
        let saved = temp.appendingPathComponent("Dropped", isDirectory: true)
        let files = await FileDrop.loadFiles(from: providers, savingInto: saved)

        #expect(files.count == 2)
        #expect(files.first?.url.standardizedFileURL == file.standardizedFileURL)
        #expect(files.first?.isOwned == false)
        let owned = try #require(files.last)
        #expect(owned.isOwned)
        #expect(owned.url.lastPathComponent == "photo.png")
        #expect(owned.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == saved.standardizedFileURL)
        #expect(try Data(contentsOf: owned.url) == png)
    }

    @Test func fileNameGetsAnExtensionAndNoSlashes() {
        let provided = URL(fileURLWithPath: "/tmp/ABC123")
        #expect(FileDrop.fileName(suggested: "a/b", provided: provided, type: .jpeg) == "a-b.jpeg")
        #expect(FileDrop.fileName(suggested: "x.png", provided: provided, type: .png) == "x.png")
        #expect(FileDrop.fileName(suggested: nil, provided: provided, type: .pdf) == "ABC123.pdf")
    }
}
