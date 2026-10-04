//
//  BluetoothDevice.swift
//  thenotch
//

import Foundation

/// A Bluetooth device that just connected, as plain values so the way it's
/// shown can be unit tested.
struct BluetoothDevice: Equatable {
    /// Battery levels in percent; `nil` when the device doesn't report one.
    struct Battery: Equatable {
        /// A single battery (headphones, keyboard, mouse…).
        var single: Int?
        /// AirPods and other earbuds: each bud and the case.
        var left: Int?
        var right: Int?
        var `case`: Int?

        var isEmpty: Bool {
            single == nil && left == nil && right == nil && `case` == nil
        }

        /// The level beside the notch: the single battery, else the lower
        /// bud (the one that runs out first).
        var headline: Int? {
            if let single { return single }
            return [left, right].compactMap { $0 }.min()
        }

        /// IOBluetooth reports 0 for "unknown".
        static func level(_ value: Int) -> Int? {
            (1...100).contains(value) ? value : nil
        }
    }

    let address: String
    var name: String
    var symbol: String
    var battery: Battery

    /// Shown under the name in the open island.
    var detail: String {
        if battery.left != nil || battery.right != nil || battery.case != nil {
            return [("Left", battery.left), ("Right", battery.right), ("Case", battery.case)]
                .compactMap { label, level in level.map { "\(label) \($0)%" } }
                .joined(separator: " · ")
        }
        if let single = battery.single {
            return "Battery \(single)%"
        }
        return "Connected"
    }

    /// One spelling of a Bluetooth address (`f8-1e-49-a0-34-a8`), so the
    /// same device matches across APIs.
    static func normalized(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: ":", with: "-")
    }

    /// The Bluetooth address in a CoreAudio device UID, such as
    /// `F8-1E-49-A0-34-A8:output`.
    static func address(fromAudioUID uid: String) -> String? {
        let candidate = String(uid.prefix { $0 != ":" })
        let parts = candidate.split(separator: "-")
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return normalized(candidate)
    }

    /// Low battery: tinted like the Mac's own low battery.
    static let lowLevel = 20

    // MARK: - Symbol

    /// Apple's vendor ID.
    static let appleVendorID = 76
    /// Product IDs of AirPods Pro and AirPods Max; other Apple earbuds are
    /// AirPods.
    static let airPodsProIDs: Set<Int> = [0x200E, 0x2014, 0x2024, 0x2027]
    static let airPodsMaxIDs: Set<Int> = [0x200A, 0x201F]

    /// SF Symbol for a device, from its vendor and product (Apple's
    /// headphones), else its Bluetooth device class.
    static func symbol(vendorID: Int, productID: Int, majorClass: Int, minorClass: Int, hasBuds: Bool) -> String {
        if vendorID == appleVendorID {
            if airPodsMaxIDs.contains(productID) { return "airpodsmax" }
            if airPodsProIDs.contains(productID) { return "airpodspro" }
            if hasBuds { return "airpods" }
        }
        switch majorClass {
        case 2:  // phone
            return "iphone"
        case 4:  // audio/video
            return minorClass == 5 ? "hifispeaker.fill" : "headphones"
        case 5:  // peripheral: keyboard/pointing in the high bits, type in the low
            if (1...2).contains(minorClass & 0xF) { return "gamecontroller.fill" }
            switch minorClass >> 4 {
            case 1: return "keyboard.fill"
            case 2: return "computermouse.fill"
            default: return "keyboard.fill"
            }
        default:
            return hasBuds ? "airpods" : "wave.3.right"
        }
    }
}
