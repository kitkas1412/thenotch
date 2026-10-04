//
//  NotificationApps.swift
//  thenotch
//

import AppKit

/// Finds the app Notification Center names (running apps first, then the
/// usual folders).
@MainActor
enum NotificationApps {
    private static var urls: [String: URL?] = [:]

    static func url(named name: String) -> URL? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.bundleURL {
            return running
        }
        if let cached = urls[name] { return cached }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        let found = folders
            .map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        urls[name] = found
        return found
    }

    static func icon(named name: String) -> NSImage? {
        url(named: name).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
