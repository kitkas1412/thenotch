//
//  BluetoothPermission.swift
//  thenotch
//

import AppKit
import CoreBluetooth

/// Bluetooth permission, needed to see devices connect. The system asks
/// the first time IOBluetooth is used (when the Bluetooth module starts).
enum BluetoothPermission {
    static var isDenied: Bool {
        let status = CBManager.authorization
        return status == .denied || status == .restricted
    }

    /// Opens System Settings › Privacy & Security › Bluetooth.
    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}
