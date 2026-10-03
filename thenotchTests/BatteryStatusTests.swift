//
//  BatteryStatusTests.swift
//  thenotchTests
//

import IOKit.ps
import Testing
@testable import thenotch

struct BatteryStatusTests {
    func description(
        current: Int = 63, max: Int = 100, onAC: Bool = false, charging: Bool = false,
        timeToEmpty: Int = 406, timeToFull: Int = 0, type: String = kIOPSInternalBatteryType
    ) -> [String: Any] {
        [
            kIOPSTypeKey: type,
            kIOPSIsPresentKey: true,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSPowerSourceStateKey: onAC ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: charging,
            kIOPSTimeToEmptyKey: timeToEmpty,
            kIOPSTimeToFullChargeKey: timeToFull,
        ]
    }

    func status(_ percent: Int, pluggedIn: Bool = false) -> BatteryStatus {
        BatteryStatus(percent: percent, isPluggedIn: pluggedIn, isCharging: pluggedIn, minutesRemaining: nil)
    }

    // MARK: Parsing

    @Test func parsesDischargingBattery() {
        #expect(BatteryStatus.from(description()) ==
                BatteryStatus(percent: 63, isPluggedIn: false, isCharging: false, minutesRemaining: 406))
    }

    @Test func parsesChargingBatteryWithTimeToFull() {
        let parsed = BatteryStatus.from(description(onAC: true, charging: true, timeToEmpty: 0, timeToFull: 45))
        #expect(parsed == BatteryStatus(percent: 63, isPluggedIn: true, isCharging: true, minutesRemaining: 45))
    }

    @Test func pluggedInButNotChargingHasNoEstimate() {
        let parsed = BatteryStatus.from(description(current: 100, onAC: true, charging: false))
        #expect(parsed?.minutesRemaining == nil)
        #expect(parsed?.percent == 100)
    }

    @Test func calculatingEstimateIsNil() {
        #expect(BatteryStatus.from(description(timeToEmpty: -1))?.minutesRemaining == nil)
    }

    @Test func percentUsesMaxCapacity() {
        #expect(BatteryStatus.from(description(current: 3000, max: 6000))?.percent == 50)
    }

    @Test func ignoresNonInternalSources() {
        #expect(BatteryStatus.from(description(type: kIOPSUPSType)) == nil)
    }

    // MARK: Peeks

    @Test func noPeekOnFirstReading() {
        #expect(status(50).peek(from: nil) == nil)
    }

    @Test func peeksWhenPluggedInAndUnplugged() {
        #expect(status(50, pluggedIn: true).peek(from: status(50)) == .pluggedIn)
        #expect(status(50).peek(from: status(50, pluggedIn: true)) == .unplugged)
    }

    @Test func peeksWhenCrossingLowThresholds() {
        #expect(status(20).peek(from: status(21)) == .low(20))
        #expect(status(10).peek(from: status(11)) == .low(10))
        #expect(status(9).peek(from: status(25)) == .low(10))
    }

    @Test func noPeekForOrdinaryChanges() {
        #expect(status(19).peek(from: status(20)) == nil)
        #expect(status(55).peek(from: status(56)) == nil)
        #expect(status(15, pluggedIn: true).peek(from: status(25, pluggedIn: true)) == nil)
    }
}
