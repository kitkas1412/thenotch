//
//  ClipboardCapture.swift
//  thenotch
//

import CoreGraphics
import Foundation
import ImageIO

/// What the pasteboard held when it changed, as plain values: read in
/// stages by `ClipboardCapture.read(…)`, then `ClipboardCapture.decide`.
struct PasteboardSnapshot: Sendable, Equatable {
    /// Every type on the pasteboard's first item.
    var types: [String]
    /// The data of the types that were read, from the first item.
    var data: [String: Data]
    /// `public.file-url` data of every pasteboard item, in order (several
    /// files copied at once are several items). When empty, the first
    /// item's `data[public.file-url]` is used.
    var fileURLs: [Data]
    /// The app that put it there, when it said so
    /// (`org.nspasteboard.source`).
    var sourceBundleID: String?
    /// The frontmost app when it changed.
    var frontmostBundleID: String?

    init(
        types: [String],
        data: [String: Data] = [:],
        fileURLs: [Data] = [],
        sourceBundleID: String? = nil,
        frontmostBundleID: String? = nil
    ) {
        self.types = types
        self.data = data
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
        self.frontmostBundleID = frontmostBundleID
    }

    /// Copied on another device (Universal Clipboard).
    var isRemote: Bool { types.contains(ClipboardCapture.Types.remote) }
}

/// What to record and how much of it.
struct CaptureSettings: Sendable, Equatable {
    /// Apps whose copies are never recorded (source or frontmost).
    var ignoredBundleIDs: Set<String> = []
    /// Record copies made on another device.
    var recordsRemote: Bool = true
    /// The type the app adds to what it puts on the pasteboard itself
    /// (pasting from the history), so it isn't recorded again.
    var ownMarkerType: String = ClipboardCapture.defaultOwnMarkerType
    var caps: Caps = Caps()

    struct Caps: Sendable, Equatable {
        /// Plain text above this is not recorded.
        var maxPlainTextBytes = 1_000_000
        /// RTF or HTML above this is dropped; the plain text is kept.
        var maxRichTextBytes = 2_000_000
        /// An image above this is not recorded.
        var maxImageBytes = 10_000_000
    }
}

/// A copy ready to become a `ClipboardItem` (`makeItem`): the image's bytes
/// are still here, the store writes them to a blob.
struct ClipboardDraft: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case text(plain: String, rtf: Data?, html: Data?)
        case image(bytes: Data, pixelSize: CGSize, uti: String)
        case files([String])
    }

    var content: Content
    var sourceBundleID: String?

    var contentHash: String {
        switch content {
        case .text(let plain, _, _): ClipboardItem.hash(text: plain)
        case .image(let bytes, _, _): ClipboardItem.hash(image: bytes)
        case .files(let paths): ClipboardItem.hash(files: paths)
        }
    }

    /// The image's bytes, if it's an image.
    var imageBytes: Data? {
        if case .image(let bytes, _, _) = content { return bytes }
        return nil
    }

    /// The history entry; an image gets the blob `blobID`.
    func makeItem(id: UUID = UUID(), blobID: UUID = UUID(), now: Date) -> ClipboardItem {
        let itemContent: ClipboardItem.Content = switch content {
        case .text(let plain, let rtf, let html):
            .text(plain: plain, rtf: rtf, html: html)
        case .image(let bytes, let pixelSize, let uti):
            .image(blobID: blobID, pixelSize: pixelSize, uti: uti, byteCount: bytes.count)
        case .files(let paths):
            .files(paths)
        }
        return ClipboardItem(
            id: id,
            createdAt: now,
            content: itemContent,
            sourceBundleID: sourceBundleID,
            contentHash: contentHash
        )
    }
}

/// Decides whether a pasteboard change is recorded, and what of it. Pure.
enum ClipboardCapture {
    enum SkipReason: Sendable, Equatable {
        /// Marked concealed or transient (passwords, generated content).
        case concealed
        /// Put there by this app.
        case ownCopy
        /// From an app the user excluded.
        case ignoredApp
        /// Copied on another device, and those aren't recorded.
        case remote
        /// Nothing recordable (no text, empty or whitespace-only text…).
        case empty
        /// Over a size cap.
        case tooLarge
    }

    enum Decision: Sendable, Equatable {
        case skip(SkipReason)
        case capture(ClipboardDraft)
    }

    enum Types {
        static let fileURL = "public.file-url"
        static let png = "public.png"
        static let tiff = "public.tiff"
        static let plainText = "public.utf8-plain-text"
        static let rtf = "public.rtf"
        static let html = "public.html"
        static let remote = "com.apple.is-remote-clipboard"
        static let source = "org.nspasteboard.source"

        /// See nspasteboard.org; plus types password managers and text
        /// expanders use.
        static let concealed: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword",
            "de.petermaurer.TransientPasteboardType",
            "net.antelle.keeweb",
            "com.typeit4me.clipping",
            "Pasteboard generator type",
        ]
    }

    static var defaultOwnMarkerType: String { AppIdentity.queueLabel("clipboard.own") }

    /// Decides from the types alone (every pasteboard item's), before any
    /// data is read: own copy, concealed, remote, the frontmost app ignored.
    static func preflight(
        types: Set<String>, frontmostBundleID: String?, settings: CaptureSettings
    ) -> SkipReason? {
        if types.contains(settings.ownMarkerType) { return .ownCopy }
        if !types.isDisjoint(with: Types.concealed) { return .concealed }
        if types.contains(Types.remote), !settings.recordsRemote { return .remote }
        if let frontmostBundleID, settings.ignoredBundleIDs.contains(frontmostBundleID) { return .ignoredApp }
        return nil
    }

    /// Reads only what's needed, in stages, and decides: `preflight` on the
    /// types; then the source app (`org.nspasteboard.source`); then file
    /// URLs; else the plain text (over its cap: skipped at once), with RTF
    /// and HTML only when it isn't blank; images only without non-empty
    /// plain text (PNG, else TIFF). Never large or promised types
    /// (`com.apple.webarchive`…).
    ///
    /// - Parameters:
    ///   - firstItemTypes: the types of the pasteboard's first item.
    ///   - allTypes: the types of every item.
    ///   - data: the first item's data for a type.
    ///   - fileURLs: `public.file-url` data of every item, in order.
    static func read(
        firstItemTypes: [String],
        allTypes: Set<String>,
        frontmostBundleID: String?,
        settings: CaptureSettings,
        data: (String) -> Data?,
        fileURLs: () -> [Data]
    ) -> Decision {
        if let reason = preflight(types: allTypes, frontmostBundleID: frontmostBundleID, settings: settings) {
            return .skip(reason)
        }
        let types = Set(firstItemTypes)
        func fetch(_ type: String) -> Data? { types.contains(type) ? data(type) : nil }

        let source = fetch(Types.source).flatMap { String(data: $0, encoding: .utf8) }
        if let source, settings.ignoredBundleIDs.contains(source) { return .skip(.ignoredApp) }
        var snapshot = PasteboardSnapshot(
            types: firstItemTypes, sourceBundleID: source, frontmostBundleID: frontmostBundleID)

        if types.contains(Types.fileURL) {
            snapshot.fileURLs = fileURLs()
            if snapshot.fileURLs.isEmpty, let first = fetch(Types.fileURL) {
                snapshot.data[Types.fileURL] = first
            }
            if !filePaths(snapshot).isEmpty { return decide(snapshot, settings: settings) }
        }

        if let text = fetch(Types.plainText), !text.isEmpty {
            guard text.count <= settings.caps.maxPlainTextBytes else { return .skip(.tooLarge) }
            snapshot.data[Types.plainText] = text
            if let plain = String(data: text, encoding: .utf8),
               !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for type in [Types.rtf, Types.html] {
                    if let rich = fetch(type), rich.count <= settings.caps.maxRichTextBytes {
                        snapshot.data[type] = rich
                    }
                }
                return decide(snapshot, settings: settings)
            }
        }

        let imageType = types.contains(Types.png) ? Types.png : Types.tiff
        if let bytes = fetch(imageType) {
            guard bytes.count <= settings.caps.maxImageBytes else { return .skip(.tooLarge) }
            snapshot.data[imageType] = bytes
        }
        return decide(snapshot, settings: settings)
    }

    /// Skips first (own copy, concealed, ignored app, remote), then
    /// records, in this order of precedence: file URLs; non-empty plain
    /// text (with RTF/HTML under their cap; over its own cap the copy is
    /// skipped, not recorded as the image); an image (PNG, else TIFF).
    static func decide(_ snapshot: PasteboardSnapshot, settings: CaptureSettings) -> Decision {
        let types = Set(snapshot.types)
        if types.contains(settings.ownMarkerType) {
            return .skip(.ownCopy)
        }
        if !types.isDisjoint(with: Types.concealed) {
            return .skip(.concealed)
        }
        let apps = [snapshot.sourceBundleID, snapshot.frontmostBundleID].compactMap { $0 }
        if apps.contains(where: settings.ignoredBundleIDs.contains) {
            return .skip(.ignoredApp)
        }
        if snapshot.isRemote, !settings.recordsRemote {
            return .skip(.remote)
        }
        let source = snapshot.sourceBundleID

        if types.contains(Types.fileURL) {
            let paths = filePaths(snapshot)
            if !paths.isEmpty {
                return .capture(ClipboardDraft(content: .files(paths), sourceBundleID: source))
            }
        }

        // Text beats an image: apps that copy text often add a picture of
        // it (Office, editors). An image is recorded only when there's no
        // non-empty plain text.
        if let textData = snapshot.data[Types.plainText], !textData.isEmpty {
            guard textData.count <= settings.caps.maxPlainTextBytes else { return .skip(.tooLarge) }
            if let plain = String(data: textData, encoding: .utf8),
               !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                func rich(_ type: String) -> Data? {
                    guard let data = snapshot.data[type], !data.isEmpty,
                          data.count <= settings.caps.maxRichTextBytes else { return nil }
                    return data
                }
                return .capture(ClipboardDraft(
                    content: .text(plain: plain, rtf: rich(Types.rtf), html: rich(Types.html)),
                    sourceBundleID: source
                ))
            }
        }

        for uti in [Types.png, Types.tiff] where types.contains(uti) {
            guard let bytes = snapshot.data[uti], !bytes.isEmpty else { continue }
            guard bytes.count <= settings.caps.maxImageBytes else { return .skip(.tooLarge) }
            guard let size = pixelSize(of: bytes) else { continue }
            return .capture(ClipboardDraft(
                content: .image(bytes: bytes, pixelSize: size, uti: uti),
                sourceBundleID: source
            ))
        }
        return .skip(.empty)
    }

    /// File paths of the copied file URLs (file reference URLs resolved).
    static func filePaths(_ snapshot: PasteboardSnapshot) -> [String] {
        var urlData = snapshot.fileURLs
        if urlData.isEmpty, let first = snapshot.data[Types.fileURL] {
            urlData = [first]
        }
        return urlData.compactMap { data in
            guard let string = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: string), url.isFileURL,
                  let path = (url as NSURL).filePathURL?.path, !path.isEmpty
            else { return nil }
            return path
        }
    }

    /// Read from the image's header, without decoding it.
    static func pixelSize(of bytes: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
