//
//  AutomationPermission.swift
//  thenotch
//

import AppKit
import CoreServices

/// Automation (Apple Events) permission for controlling another app.
enum AutomationPermission {
    enum Status: Equatable {
        case granted
        case denied
        /// The user hasn't been asked yet.
        case notDetermined
        /// The target app isn't running, so the status can't be checked.
        case unknown
    }

    /// Checks (and, with `prompt`, asks for) permission to send Apple Events
    /// to `bundleID`. Blocks while the system prompt is shown, so call it
    /// off the main thread.
    static func status(for bundleID: String, prompt: Bool) -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = target.aeDesc else { return .unknown }
        let result = AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, prompt)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .unknown  // procNotFound: the app isn't running
        }
    }

    /// Opens System Settings › Privacy & Security › Automation.
    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
