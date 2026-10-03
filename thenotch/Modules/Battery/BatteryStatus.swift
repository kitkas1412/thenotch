//
//  BatteryStatus.swift
//  thenotch
//

import Foundation
import IOKit.ps

/// State of the internal battery.
struct BatteryStatus: Equatable {
    /// 0...100
    var percent: Int
    /// Connected to a charger (even if not currently charging).
    var isPluggedIn: Bool
    var isCharging: Bool
    /// Minutes until empty (on battery) or full (charging), if estimated.
    var minutesRemaining: Int?

    /// Why the island should briefly show the battery.
    enum Peek: Equatable {
        case pluggedIn
        case unplugged
        /// Dropped to or below this percentage while on battery.
        case low(Int)
    }

    /// Percentages that trigger a low-battery peek, highest first.
    static let lowThresholds = [20, 10]

    /// Parses an `IOPSGetPowerSourceDescription` dictionary. Returns `nil`
    /// for anything that isn't the internal battery (e.g. a UPS).
    static func from(_ description: [String: Any]) -> BatteryStatus? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              description[kIOPSIsPresentKey] as? Bool ?? true,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return nil }

        let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let timeKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        // -1 means "still calculating"; 0 is reported when not applicable.
        let minutes = (description[timeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

        return BatteryStatus(
            percent: Swift.min(Swift.max(current * 100 / max, 0), 100),
            isPluggedIn: pluggedIn,
            isCharging: charging,
            minutesRemaining: pluggedIn && !charging ? nil : minutes
        )
    }

    /// The peek to show when the status changes from `previous` to `self`.
    func peek(from previous: BatteryStatus?) -> Peek? {
        guard let previous else { return nil }  // first reading at launch
        if isPluggedIn != previous.isPluggedIn {
            return isPluggedIn ? .pluggedIn : .unplugged
        }
        guard !isPluggedIn else { return nil }
        // Crossing a threshold downwards, e.g. 21% → 20%.
        if let threshold = Self.lowThresholds.last(where: { percent <= $0 && previous.percent > $0 }) {
            return .low(threshold)
        }
        return nil
    }
}
