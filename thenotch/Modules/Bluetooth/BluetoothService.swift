//
//  BluetoothService.swift
//  thenotch
//

import CoreAudio
import Foundation
@preconcurrency import IOBluetooth
import IOKit
import os

/// Reports Bluetooth devices as they connect, with their battery.
///
/// Two events count as connecting: a new Bluetooth connection, and the
/// Mac's sound switching to a Bluetooth device. AirPods often stay
/// connected in their case, so taking them out only switches the sound
/// (that's when macOS shows its own AirPods card).
///
/// IOBluetooth also reports the devices already connected when it starts
/// listening; those are skipped, so only a new connection is reported.
/// Using IOBluetooth needs Bluetooth permission (the system asks once).
@MainActor
final class BluetoothService: NSObject {
    /// A device connected (or its battery became known since).
    var onConnect: ((BluetoothDevice) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Connected devices, so a repeated notification isn't a new connection.
    private var connected: Set<String> = []
    private var batteryTasks: [String: Task<Void, Never>] = [:]
    /// UID of the default output, to notice the sound moving to a device.
    private var outputUID: String?
    private var outputListener: AudioObjectPropertyListenerBlock?

    /// AirPods report their battery a moment after connecting (until then,
    /// none, or the levels from when they were last connected).
    static let batteryRetries: [Duration] = [.seconds(1), .seconds(2)]

    func start() {
        guard connectNotification == nil else { return }
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where device.isConnected() {
            if let address = device.addressString {
                connected.insert(address)
                watchDisconnect(of: device)
            }
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        Log.bluetooth.notice("Watching for connections; \(self.connected.count) device(s) already connected")
        watchOutput()
    }

    func stop() {
        if let outputListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
        }
        outputListener = nil
        outputUID = nil
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        batteryTasks.values.forEach { $0.cancel() }
        batteryTasks.removeAll()
        connected.removeAll()
    }

    // IOBluetooth calls these on the main thread or on its own queue (the
    // same connection can arrive on both): hop to the main thread.

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.connected(device)
            }
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.disconnected(device)
            }
        }
    }

    private func connected(_ device: IOBluetoothDevice) {
        guard let address = device.addressString, connected.insert(address).inserted else { return }
        watchDisconnect(of: device)
        let info = Self.info(of: device, address: address)
        Log.bluetooth.notice("Connected: \(info.name, privacy: .private) (\(info.symbol, privacy: .public)), battery \(info.battery.headline ?? -1)")
        onConnect?(info)
        readBatteryLater(of: device, address: address, shown: info)
    }

    private func disconnected(_ device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        connected.remove(address)
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        batteryTasks.removeValue(forKey: address)?.cancel()
    }

    // MARK: - Sound output

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func watchOutput() {
        outputUID = Self.defaultOutput()?.uid
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.outputChanged()
            }
        }
        var address = Self.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            outputListener = listener
        }
    }

    /// The sound moved to another device: if it's a Bluetooth one, report it.
    private func outputChanged() {
        let output = Self.defaultOutput()
        guard output?.uid != outputUID else { return }
        outputUID = output?.uid
        guard let output, output.isBluetooth,
              let address = BluetoothDevice.address(fromAudioUID: output.uid),
              let device = IOBluetoothDevice(addressString: address)
        else { return }
        let info = Self.info(of: device, address: address)
        Log.bluetooth.notice("Sound moved to \(info.name, privacy: .private), battery \(info.battery.headline ?? -1)")
        onConnect?(info)
        readBatteryLater(of: device, address: address, shown: info)
    }

    private static func defaultOutput() -> (uid: String, isBluetooth: Bool)? {
        var address = defaultOutputAddress
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown
        else { return nil }

        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &size, &uid) == noErr,
              let uid = uid?.takeRetainedValue() as String?
        else { return nil }

        var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &size, &transport)
        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        return (uid, isBluetooth)
    }

    // MARK: - Connections

    private func watchDisconnect(of device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    private func readBatteryLater(of device: IOBluetoothDevice, address: String, shown: BluetoothDevice) {
        batteryTasks[address]?.cancel()
        batteryTasks[address] = Task { [weak self] in
            var shown = shown
            for delay in Self.batteryRetries {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.connected.contains(address) else { return }
                let info = Self.info(of: device, address: address)
                if info != shown {
                    Log.bluetooth.notice("Battery updated: \(info.detail, privacy: .public)")
                    shown = info
                    self.onConnect?(info)
                }
            }
            self?.batteryTasks[address] = nil
        }
    }

    // MARK: - Reading a device

    private static func info(of device: IOBluetoothDevice, address: String) -> BluetoothDevice {
        var battery = BluetoothDevice.Battery(
            single: level(of: device, "batteryPercentSingle"),
            left: level(of: device, "batteryPercentLeft"),
            right: level(of: device, "batteryPercentRight"),
            case: level(of: device, "batteryPercentCase")
        )
        if battery.isEmpty {
            battery.single = hidBatteryLevel(address: address)
        }
        return BluetoothDevice(
            address: BluetoothDevice.normalized(address),
            name: device.nameOrAddress ?? "Bluetooth device",
            symbol: BluetoothDevice.symbol(
                vendorID: integer(of: device, "vendorID") ?? 0,
                productID: integer(of: device, "productID") ?? 0,
                majorClass: Int(device.deviceClassMajor),
                minorClass: Int(device.deviceClassMinor),
                hasBuds: battery.left != nil || battery.right != nil
            ),
            battery: battery
        )
    }

    /// Battery levels and product IDs aren't public API: read them only if
    /// the device answers to them, so a macOS change just hides the level.
    private static func integer(of device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: Selector(key)) else { return nil }
        return (device.value(forKey: key) as? NSNumber)?.intValue
    }

    private static func level(of device: IOBluetoothDevice, _ key: String) -> Int? {
        integer(of: device, key).flatMap(BluetoothDevice.Battery.level)
    }

    /// Magic Keyboard, Mouse and Trackpad report their battery through
    /// their HID service in the I/O Registry instead.
    private static func hidBatteryLevel(address: String) -> Int? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let wanted = BluetoothDevice.normalized(address)
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let deviceAddress = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  BluetoothDevice.normalized(deviceAddress) == wanted,
                  let percent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            else { continue }
            return BluetoothDevice.Battery.level(percent)
        }
        return nil
    }
}
