//
//  Log.swift
//  thenotch
//

import Foundation
import os

/// Unified logging, viewable in Console.app or with
/// `log stream --level debug --predicate 'subsystem == "<bundle id>"'`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "thenotch"

    /// Dragging files onto the island and dropping them.
    static let drop = Logger(subsystem: subsystem, category: "drop")
    /// The volume and brightness keys.
    static let hud = Logger(subsystem: subsystem, category: "hud")
    /// Bluetooth devices connecting.
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    /// Notification Center's banners (never their text).
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    /// Claude Code's hooks.
    static let claude = Logger(subsystem: subsystem, category: "claude")
}
