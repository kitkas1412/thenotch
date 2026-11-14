//
//  PermissionCenter.swift
//  thenotch
//

import AppKit
import ApplicationServices
import CoreBluetooth
import CoreGraphics
import IOKit.hid

/// The privacy permissions the app's tools can need.
enum Permission: String, CaseIterable {
    case accessibility
    case screenRecording
    case inputMonitoring
    case automation
    case bluetooth

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .inputMonitoring: "Input Monitoring"
        case .automation: "Automation"
        case .bluetooth: "Bluetooth"
        }
    }

    /// The System Settings › Privacy & Security pane for this permission.
    var systemSettingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .automation: anchor = "Privacy_Automation"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    /// The user hasn't been asked yet.
    case notDetermined
    /// Can't be told without more context (Automation is per target app).
    case unknown
}

/// One place to read, request and open the settings of every permission.
/// `status(_:)` never shows a system prompt; only `request(_:)` can.
enum PermissionCenter {
    // MARK: Pure mapping

    static func status(hidAccess: IOHIDAccessType) -> PermissionStatus {
        switch hidAccess {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        case kIOHIDAccessTypeUnknown: .notDetermined
        default: .unknown
        }
    }

    static func status(bluetooth authorization: CBManagerAuthorization) -> PermissionStatus {
        switch authorization {
        case .allowedAlways: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    // MARK: Status (prompt-free)

    /// Current status. Never prompts. Automation is per target app, so the
    /// generic case is `.unknown`; use `AutomationPermission.status(for:prompt:)`
    /// with `prompt: false` for a specific app.
    static func status(_ permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AccessibilityPermission.isTrusted ? .granted : .denied
        case .screenRecording:
            // CGPreflightScreenCaptureAccess never prompts; it can't tell
            // "not asked" from "denied".
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .inputMonitoring:
            return status(hidAccess: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
        case .automation:
            return .unknown
        case .bluetooth:
            return status(bluetooth: CBManager.authorization)
        }
    }

    // MARK: Request (may prompt)

    /// Asks for the permission. Accessibility, Screen Recording, Input
    /// Monitoring and Bluetooth can show a system prompt. Automation can't be
    /// requested generically (it needs a target app), so it opens its pane.
    @MainActor
    static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            AccessibilityPermission.request()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .automation:
            openSettings(.automation)
        case .bluetooth:
            // Creating a central manager is what triggers the prompt.
            if status(.bluetooth) == .notDetermined, bluetoothProbe == nil {
                bluetoothProbe = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            }
        }
    }

    @MainActor
    static func openSettings(_ permission: Permission) {
        if let url = permission.systemSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Kept alive so the Bluetooth prompt isn't torn down with its manager.
    @MainActor
    private static var bluetoothProbe: CBCentralManager?
}
