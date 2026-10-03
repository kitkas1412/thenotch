//
//  FileDrop.swift
//  thenotch
//

import Foundation
import UniformTypeIdentifiers

/// A file taken from a drop.
struct DroppedFile: Equatable {
    let url: URL
    /// Saved by us (promised file, or content without a file such as an
    /// image from a browser) into `FileDrop.directory`; whoever keeps it
    /// deletes it when done. Otherwise the user's own file, referenced only.
    let isOwned: Bool
}

/// Reads the files out of a SwiftUI drop.
enum FileDrop {
    /// Types accepted by `onDrop`.
    static let acceptedTypes: [UTType] = [.fileURL] + contentTypes
    /// Content saved as a file when a dropped item isn't a file URL.
    static let contentTypes: [UTType] = [.image, .pdf, .movie, .audio]

    /// Where dropped content is saved, one folder per file:
    /// `~/Library/Application Support/<bundle id>/Dropped/<uuid>/<name>`.
    static var directory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "thenotch", isDirectory: true)
            .appendingPathComponent("Dropped", isDirectory: true)
    }

    /// Files carried by `providers`, in order. A file URL is used as is;
    /// other content (promised files, images…) is saved into `directory`.
    /// Items that are neither (text, web links) are skipped.
    static func loadFiles(from providers: [NSItemProvider], savingInto directory: URL = directory) async -> [DroppedFile] {
        var files: [DroppedFile] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await loadURL(from: provider), url.isFileURL {
                    files.append(DroppedFile(url: url, isOwned: false))
                }
            } else if let url = await saveContent(of: provider, into: directory) {
                files.append(DroppedFile(url: url, isOwned: true))
            }
        }
        return files
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// Asks the provider for a file of its first accepted content type
    /// (resolving a file promise if needed) and copies it into its own
    /// folder under `directory`: the provided file is deleted once the
    /// callback returns.
    private static func saveContent(of provider: NSItemProvider, into directory: URL) async -> URL? {
        let type = provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first { type in contentTypes.contains { type.conforms(to: $0) } }
        guard let type else { return nil }
        let suggestedName = provider.suggestedName

        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { file, _ in
                guard let file else {
                    continuation.resume(returning: nil)
                    return
                }
                let name = fileName(suggested: suggestedName, provided: file, type: type)
                let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let destination = folder.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: file, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// The provider's suggested name, else the provided file's; with an
    /// extension matching `type` if it has none.
    static func fileName(suggested: String?, provided: URL, type: UTType) -> String {
        var name = suggested.flatMap { $0.isEmpty ? nil : $0 } ?? provided.lastPathComponent
        name = name.replacingOccurrences(of: "/", with: "-")
        if (name as NSString).pathExtension.isEmpty, let ext = type.preferredFilenameExtension {
            name += ".\(ext)"
        }
        return name
    }
}
