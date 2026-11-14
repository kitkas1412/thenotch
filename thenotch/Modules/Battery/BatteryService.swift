//
//  BatteryService.swift
//  thenotch
//

import Foundation
import IOKit.ps
import Observation

/// Internal battery state, updated by IOKit power-source notifications
/// (no polling).
@MainActor
@Observable
final class BatteryService {
    /// `nil` on Macs without a battery.
    private(set) var status: BatteryStatus?

    /// Called with the new and previous status on every change.
    @ObservationIgnored var onChange: ((BatteryStatus?, BatteryStatus?) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // The callback fires on the main run loop.
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                service.update()
            }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
        update()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        status = nil
    }

    private func update() {
        let new = Self.readInternalBattery()
        guard new != status else { return }
        let previous = status
        status = new
        onChange?(new, previous)
    }

    private static func readInternalBattery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let status = BatteryStatus.from(description) {
                return status
            }
        }
        return nil
    }
}
