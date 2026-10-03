//
//  FileDrop.swift
//  thenotch
//

import Foundation
import UniformTypeIdentifiers

/// Reads the files out of a SwiftUI drop.
enum FileDrop {
    /// File URLs carried by `providers`, in order. Items that aren't files
    /// (text, web links, file promises) are skipped.
    static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadURL(from: provider), url.isFileURL {
                urls.append(url)
            }
        }
        return urls
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
