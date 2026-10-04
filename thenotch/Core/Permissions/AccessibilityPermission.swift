//
//  AccessibilityPermission.swift
//  thenotch
//

import AppKit
import ApplicationServices

/// Accessibility permission, needed to intercept keys with an event tap
/// (the volume and brightness keys).
enum AccessibilityPermission {
    /// Posted (distributed) when any app's Accessibility access changes.
    /// It can arrive a moment before `isTrusted` reflects the change.
    static let didChangeNotification = Notification.Name("com.apple.accessibility.api")

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt, which leads to System Settings, unless the
    /// app is already trusted.
    static func request() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens System Settings › Privacy & Security › Accessibility.
    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
