//
//  ClipboardCaptureTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct ClipboardCaptureTests {
    typealias Types = ClipboardCapture.Types

    static func text(_ string: String, extra: [String] = [], more: [String: Data] = [:]) -> PasteboardSnapshot {
        var data = more
        data[Types.plainText] = Data(string.utf8)
        return PasteboardSnapshot(types: [Types.plainText] + extra, data: data)
    }

    static func fileURLData(_ path: String) -> Data { Data(URL(fileURLWithPath: path).absoluteString.utf8) }

    func decide(_ snapshot: PasteboardSnapshot, _ settings: CaptureSettings = CaptureSettings()) -> ClipboardCapture.Decision {
        ClipboardCapture.decide(snapshot, settings: settings)
    }

    // MARK: Skips

    @Test(arguments: Array(Types.concealed).sorted())
    func concealedMarkerSkips(marker: String) {
        #expect(decide(Self.text("secret", extra: [marker])) == .skip(.concealed))
    }

    @Test func ownMarkerSkips() {
        #expect(decide(Self.text("x", extra: [ClipboardCapture.defaultOwnMarkerType])) == .skip(.ownCopy))
    }

    @Test func customOwnMarkerSkips() {
        var settings = CaptureSettings()
        settings.ownMarkerType = "test.own"
        #expect(decide(Self.text("x", extra: ["test.own"]), settings) == .skip(.ownCopy))
    }

    @Test func ownMarkerWinsOverConcealed() {
        let snapshot = Self.text("x", extra: ["org.nspasteboard.ConcealedType", ClipboardCapture.defaultOwnMarkerType])
        #expect(decide(snapshot) == .skip(.ownCopy))
    }

    @Test func ignoredAppSkipsBySourceAndByFrontmost() {
        var settings = CaptureSettings()
        settings.ignoredBundleIDs = ["com.example.ignored"]
        var bySource = Self.text("x")
        bySource.sourceBundleID = "com.example.ignored"
        var byFront = Self.text("x")
        byFront.frontmostBundleID = "com.example.ignored"
        var other = Self.text("x")
        other.sourceBundleID = "com.example.other"
        other.frontmostBundleID = "com.example.other2"
        #expect(decide(bySource, settings) == .skip(.ignoredApp))
        #expect(decide(byFront, settings) == .skip(.ignoredApp))
        if case .capture = decide(other, settings) {} else { Issue.record("other apps must be recorded") }
    }

    @Test func remoteSkippedOnlyWhenNotRecorded() {
        let snapshot = Self.text("x", extra: [Types.remote])
        #expect(snapshot.isRemote)
        var settings = CaptureSettings()
        settings.recordsRemote = false
        #expect(decide(snapshot, settings) == .skip(.remote))
        settings.recordsRemote = true
        if case .capture = decide(snapshot, settings) {} else { Issue.record("remote must be recorded") }
        // A local copy is unaffected.
        settings.recordsRemote = false
        if case .capture = decide(Self.text("x"), settings) {} else { Issue.record("local must be recorded") }
    }

    @Test(arguments: ["", "   ", "\n\t \n"])
    func blankTextIsEmpty(text: String) {
        #expect(decide(Self.text(text)) == .skip(.empty))
    }

    @Test func nothingRecordableIsEmpty() {
        #expect(decide(PasteboardSnapshot(types: ["com.example.unknown"])) == .skip(.empty))
    }

    // MARK: Capture and precedence

    @Test func textKeepsRichPartsAndSource() throws {
        var snapshot = Self.text("hello", more: [Types.rtf: Data("r".utf8), Types.html: Data("h".utf8)])
        snapshot.sourceBundleID = "com.example.src"
        let expected = ClipboardDraft(
            content: .text(plain: "hello", rtf: Data("r".utf8), html: Data("h".utf8)),
            sourceBundleID: "com.example.src")
        #expect(decide(snapshot) == .capture(expected))
    }

    @Test func filesBeatTextAndImage() {
        let snapshot = PasteboardSnapshot(
            types: [Types.fileURL, Types.plainText, Types.png],
            data: [Types.fileURL: Self.fileURLData("/tmp/a.txt"), Types.plainText: Data("a.txt".utf8),
                   Types.png: ClipboardFixtures.png])
        #expect(decide(snapshot) == .capture(ClipboardDraft(content: .files(["/tmp/a.txt"]), sourceBundleID: nil)))
    }

    @Test func multipleFileURLsKeepOrder() {
        let snapshot = PasteboardSnapshot(
            types: [Types.fileURL],
            fileURLs: [Self.fileURLData("/tmp/b.txt"), Self.fileURLData("/tmp/a.txt")])
        #expect(decide(snapshot) == .capture(ClipboardDraft(content: .files(["/tmp/b.txt", "/tmp/a.txt"]), sourceBundleID: nil)))
    }

    @Test func nonFileURLFallsThroughToText() {
        let snapshot = PasteboardSnapshot(
            types: [Types.fileURL, Types.plainText],
            data: [Types.fileURL: Data("https://example.com".utf8), Types.plainText: Data("hi".utf8)])
        #expect(decide(snapshot) == .capture(ClipboardDraft(content: .text(plain: "hi", rtf: nil, html: nil), sourceBundleID: nil)))
    }

    @Test func textBeatsImage() {
        let snapshot = Self.text("words", extra: [Types.png], more: [Types.png: ClipboardFixtures.png])
        #expect(decide(snapshot) == .capture(ClipboardDraft(content: .text(plain: "words", rtf: nil, html: nil), sourceBundleID: nil)))
    }

    @Test func imageRecordedWhenTextIsBlank() throws {
        let snapshot = Self.text("  ", extra: [Types.png], more: [Types.png: ClipboardFixtures.png])
        guard case .capture(let draft) = decide(snapshot), case .image(let bytes, let size, let uti) = draft.content else {
            Issue.record("expected an image"); return
        }
        #expect(bytes == ClipboardFixtures.png)
        #expect(size == CGSize(width: 1, height: 1))
        #expect(uti == Types.png)
    }

    @Test func pngBeatsTiffAndTiffIsUsedAlone() {
        let both = PasteboardSnapshot(
            types: [Types.png, Types.tiff],
            data: [Types.png: ClipboardFixtures.png, Types.tiff: ClipboardFixtures.tiff])
        if case .capture(let draft) = decide(both), case .image(_, _, let uti) = draft.content {
            #expect(uti == Types.png)
        } else { Issue.record("expected png") }
        let tiff = PasteboardSnapshot(types: [Types.tiff], data: [Types.tiff: ClipboardFixtures.tiff])
        if case .capture(let draft) = decide(tiff), case .image(_, _, let uti) = draft.content {
            #expect(uti == Types.tiff)
        } else { Issue.record("expected tiff") }
    }

    @Test func undecodableImageIsEmpty() {
        let snapshot = PasteboardSnapshot(types: [Types.png], data: [Types.png: Data("not an image".utf8)])
        #expect(decide(snapshot) == .skip(.empty))
    }

    // MARK: Caps

    @Test func plainTextCapBoundary() {
        var settings = CaptureSettings()
        settings.caps.maxPlainTextBytes = 10
        if case .capture = decide(Self.text(String(repeating: "a", count: 10)), settings) {} else { Issue.record("at cap must be kept") }
        #expect(decide(Self.text(String(repeating: "a", count: 11)), settings) == .skip(.tooLarge))
    }

    @Test func oversizedTextIsNotRecordedAsItsImage() {
        var settings = CaptureSettings()
        settings.caps.maxPlainTextBytes = 3
        let snapshot = Self.text("long text", extra: [Types.png], more: [Types.png: ClipboardFixtures.png])
        #expect(decide(snapshot, settings) == .skip(.tooLarge))
    }

    @Test func richPartsOverCapAreDroppedButTextKept() {
        var settings = CaptureSettings()
        settings.caps.maxRichTextBytes = 4
        let snapshot = Self.text("t", more: [Types.rtf: Data(repeating: 1, count: 4), Types.html: Data(repeating: 1, count: 5)])
        #expect(decide(snapshot, settings) == .capture(ClipboardDraft(
            content: .text(plain: "t", rtf: Data(repeating: 1, count: 4), html: nil), sourceBundleID: nil)))
    }

    @Test func imageCapBoundary() {
        var settings = CaptureSettings()
        let snapshot = PasteboardSnapshot(types: [Types.png], data: [Types.png: ClipboardFixtures.png])
        settings.caps.maxImageBytes = ClipboardFixtures.png.count
        if case .capture = decide(snapshot, settings) {} else { Issue.record("at cap must be kept") }
        settings.caps.maxImageBytes = ClipboardFixtures.png.count - 1
        #expect(decide(snapshot, settings) == .skip(.tooLarge))
    }

    @Test func defaultCaps() {
        let caps = CaptureSettings.Caps()
        #expect(caps.maxPlainTextBytes == 1_000_000)
        #expect(caps.maxRichTextBytes == 2_000_000)
        #expect(caps.maxImageBytes == 10_000_000)
    }

    // MARK: preflight

    @Test func preflightSkipsOnTypesAlone() {
        var settings = CaptureSettings()
        settings.ignoredBundleIDs = ["com.example.ignored"]
        settings.recordsRemote = false
        func check(_ types: Set<String>, front: String? = nil) -> ClipboardCapture.SkipReason? {
            ClipboardCapture.preflight(types: types, frontmostBundleID: front, settings: settings)
        }
        #expect(check([Types.plainText, ClipboardCapture.defaultOwnMarkerType]) == .ownCopy)
        #expect(check([Types.plainText, "org.nspasteboard.TransientType"]) == .concealed)
        #expect(check([Types.plainText, Types.remote]) == .remote)
        #expect(check([Types.plainText], front: "com.example.ignored") == .ignoredApp)
        #expect(check([Types.plainText], front: "com.example.other") == nil)
        settings.recordsRemote = true
        #expect(check([Types.plainText, Types.remote]) == nil)
    }

    // MARK: read

    /// Runs `read` over a fake pasteboard; returns the decision and the
    /// types whose data was read, in order.
    func read(
        _ items: [[String: Data]], front: String? = nil, settings: CaptureSettings = CaptureSettings()
    ) -> (ClipboardCapture.Decision, [String]) {
        var reads: [String] = []
        let first = items.first ?? [:]
        let decision = ClipboardCapture.read(
            firstItemTypes: first.keys.sorted(),
            allTypes: Set(items.flatMap(\.keys)),
            frontmostBundleID: front,
            settings: settings,
            data: { type in
                reads.append(type)
                return first[type]
            },
            fileURLs: {
                reads.append("fileURLs")
                return items.compactMap { $0[Types.fileURL] }
            })
        return (decision, reads)
    }

    @Test func skippedCopiesReadNoData() {
        var settings = CaptureSettings()
        settings.ignoredBundleIDs = ["com.example.ignored"]
        settings.recordsRemote = false
        let text = Data("secret".utf8)
        // The marker on a later item counts too.
        let concealed = read([[Types.plainText: text], ["org.nspasteboard.ConcealedType": Data()]])
        #expect(concealed.0 == .skip(.concealed) && concealed.1.isEmpty)
        let remote = read([[Types.plainText: text, Types.remote: Data()]], settings: settings)
        #expect(remote.0 == .skip(.remote) && remote.1.isEmpty)
        let front = read([[Types.plainText: text]], front: "com.example.ignored", settings: settings)
        #expect(front.0 == .skip(.ignoredApp) && front.1.isEmpty)
    }

    @Test func ignoredSourceReadsOnlyTheSource() {
        var settings = CaptureSettings()
        settings.ignoredBundleIDs = ["com.example.ignored"]
        let (decision, reads) = read(
            [[Types.plainText: Data("x".utf8), Types.source: Data("com.example.ignored".utf8)]], settings: settings)
        #expect(decision == .skip(.ignoredApp))
        #expect(reads == [Types.source])
    }

    @Test func filesAreReadBeforeAndInsteadOfText() {
        let (decision, reads) = read([
            [Types.fileURL: Self.fileURLData("/tmp/a.txt"), Types.plainText: Data("a.txt".utf8)],
            [Types.fileURL: Self.fileURLData("/tmp/b.txt")],
        ])
        #expect(decision == .capture(ClipboardDraft(content: .files(["/tmp/a.txt", "/tmp/b.txt"]), sourceBundleID: nil)))
        #expect(reads == ["fileURLs"])
    }

    @Test func textSkipsImagesAndHeavyTypes() {
        let (decision, reads) = read([[
            Types.plainText: Data("hello".utf8), Types.rtf: Data("r".utf8), Types.png: ClipboardFixtures.png,
            Types.tiff: ClipboardFixtures.tiff, "com.apple.webarchive": Data([1]),
        ]])
        #expect(decision == .capture(ClipboardDraft(
            content: .text(plain: "hello", rtf: Data("r".utf8), html: nil), sourceBundleID: nil)))
        #expect(reads == [Types.plainText, Types.rtf])
    }

    @Test func oversizedTextStopsBeforeRichPartsAndImages() {
        var settings = CaptureSettings()
        settings.caps.maxPlainTextBytes = 3
        let (decision, reads) = read([[
            Types.plainText: Data("long text".utf8), Types.html: Data("h".utf8), Types.png: ClipboardFixtures.png,
        ]], settings: settings)
        #expect(decision == .skip(.tooLarge))
        #expect(reads == [Types.plainText])
    }

    @Test func imageIsReadOnlyWithoutTextAndPrefersPng() {
        let (decision, reads) = read([[
            Types.plainText: Data("  ".utf8), Types.png: ClipboardFixtures.png, Types.tiff: ClipboardFixtures.tiff,
        ]])
        if case .capture(let draft) = decision, case .image(_, _, let uti) = draft.content {
            #expect(uti == Types.png)
        } else {
            Issue.record("the image must be recorded")
        }
        #expect(reads == [Types.plainText, Types.png])
        let tiffOnly = read([[Types.tiff: ClipboardFixtures.tiff]])
        #expect(tiffOnly.1 == [Types.tiff])
    }

    @Test func oversizedImageIsSkipped() {
        var settings = CaptureSettings()
        settings.caps.maxImageBytes = 1
        #expect(read([[Types.png: ClipboardFixtures.png]], settings: settings).0 == .skip(.tooLarge))
    }

    @Test func richPartOverCapIsDroppedWhenRead() {
        var settings = CaptureSettings()
        settings.caps.maxRichTextBytes = 2
        let (decision, _) = read([[
            Types.plainText: Data("t".utf8), Types.rtf: Data("rtf".utf8), Types.html: Data("h".utf8),
        ]], settings: settings)
        #expect(decision == .capture(ClipboardDraft(
            content: .text(plain: "t", rtf: nil, html: Data("h".utf8)), sourceBundleID: nil)))
    }
}
