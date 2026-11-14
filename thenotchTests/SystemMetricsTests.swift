//
//  SystemMetricsTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct SystemMetricsTests {
    private func ticks(_ user: UInt64, _ system: UInt64, _ idle: UInt64, _ nice: UInt64 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func cpuTicksTotalSumsAllCounters() {
        #expect(ticks(1, 2, 3, 4).total == 10)
    }

    @Test func cpuFractionIsBusyShareOfTheDelta() {
        let fraction = CPUUsage.fraction(previous: ticks(100, 100, 800), current: ticks(130, 120, 850))
        #expect(fraction == 0.5)
    }

    @Test func cpuFractionCountsNiceAsBusy() {
        #expect(CPUUsage.fraction(previous: ticks(0, 0, 0, 0), current: ticks(0, 0, 50, 50)) == 0.5)
    }

    @Test func cpuFractionBoundsAreZeroAndOne() {
        #expect(CPUUsage.fraction(previous: ticks(0, 0, 0), current: ticks(0, 0, 10)) == 0)
        #expect(CPUUsage.fraction(previous: ticks(0, 0, 0), current: ticks(10, 0, 0)) == 1)
    }

    @Test func cpuFractionIsNilWithoutDelta() {
        let t = ticks(5, 5, 5)
        #expect(CPUUsage.fraction(previous: t, current: t) == nil)
    }

    @Test(arguments: [
        (CPUTicks(user: 10, system: 10, idle: 10, nice: 0), CPUTicks(user: 9, system: 10, idle: 10, nice: 0)),
        (CPUTicks(user: 10, system: 10, idle: 10, nice: 0), CPUTicks(user: 20, system: 9, idle: 20, nice: 0)),
        (CPUTicks(user: 10, system: 10, idle: 10, nice: 0), CPUTicks(user: 20, system: 20, idle: 9, nice: 0)),
        (CPUTicks(user: 10, system: 10, idle: 10, nice: 1), CPUTicks(user: 20, system: 20, idle: 20, nice: 0)),
    ])
    func cpuFractionIsNilWhenACounterWentBackwards(previous: CPUTicks, current: CPUTicks) {
        #expect(CPUUsage.fraction(previous: previous, current: current) == nil)
    }

    @Test func memoryUsedIsActivePlusWiredPlusCompressed() {
        let usage = MemoryUsage.from(activePages: 10, wiredPages: 20, compressedPages: 30,
                                     pageSize: 4096, total: 1_000_000)
        #expect(usage.used == 60 * 4096)
        #expect(usage.total == 1_000_000)
        #expect(abs(usage.fraction - Double(60 * 4096) / 1_000_000) < 1e-12)
    }

    @Test func memoryUsedIsCappedAtTotal() {
        let usage = MemoryUsage.from(activePages: 1000, wiredPages: 1000, compressedPages: 1000,
                                     pageSize: 4096, total: 4096)
        #expect(usage.used == 4096)
        #expect(usage.fraction == 1)
    }

    @Test func memoryFractionWithZeroTotalIsZero() {
        #expect(MemoryUsage(used: 0, total: 0).fraction == 0)
        #expect(MemoryUsage.from(activePages: 1, wiredPages: 1, compressedPages: 1, pageSize: 1, total: 0).fraction == 0)
    }

    @Test func networkRateDividesDeltaByElapsed() {
        #expect(NetworkRate.bytesPerSecond(previous: 1000, current: 5000, elapsed: 2) == 2000)
        #expect(NetworkRate.bytesPerSecond(previous: 10, current: 10, elapsed: 1) == 0)
    }

    @Test func networkRateIsZeroWhenCounterDecreases() {
        #expect(NetworkRate.bytesPerSecond(previous: 5000, current: 100, elapsed: 1) == 0)
    }

    @Test(arguments: [0.0, -1.0])
    func networkRateIsZeroWithoutPositiveElapsed(elapsed: Double) {
        #expect(NetworkRate.bytesPerSecond(previous: 0, current: 1000, elapsed: elapsed) == 0)
    }

    @Test func diskUsedAndFraction() {
        let disk = DiskUsage(available: 250, total: 1000)
        #expect(disk.used == 750)
        #expect(disk.fraction == 0.75)
    }

    @Test func diskEdgeCases() {
        #expect(DiskUsage(available: 0, total: 0).fraction == 0)
        #expect(DiskUsage(available: 500, total: 0).used == 0)
        let over = DiskUsage(available: 2000, total: 1000)
        #expect(over.used == 0)
        #expect(over.fraction == 0)
    }

    @Test(arguments: [
        (0.0, "0%"), (1.0, "100%"), (0.12, "12%"), (0.125, "13%"), (0.124, "12%"),
        (-0.5, "0%"), (1.7, "100%"), (0.995, "100%"),
    ])
    func percentFormatting(fraction: Double, expected: String) {
        #expect(MetricFormat.percent(fraction) == expected)
    }

    @Test(arguments: [
        (0.0, "0 B/s"), (512.0, "512 B/s"), (999.0, "999 B/s"), (1000.0, "1.0 KB/s"),
        (1234.0, "1.2 KB/s"), (1_200_000.0, "1.2 MB/s"), (9_940.0, "9.9 KB/s"),
        (9_950.0, "10 KB/s"), (10_000.0, "10 KB/s"), (12_000_000.0, "12 MB/s"),
        (999_400.0, "999 KB/s"), (999_500.0, "1.0 MB/s"), (-5.0, "0 B/s"),
        (2_500_000_000.0, "2.5 GB/s"),
    ])
    func rateFormatting(value: Double, expected: String) {
        #expect(MetricFormat.rate(value) == expected)
    }

    @Test(arguments: [
        (UInt64(120_000_000_000), "120 GB"), (UInt64(1_200_000_000_000), "1.2 TB"),
        (UInt64(0), "0 B"), (UInt64(500_000_000_000), "500 GB"),
    ])
    func capacityFormatting(bytes: UInt64, expected: String) {
        #expect(MetricFormat.capacity(bytes) == expected)
    }

    @Test(arguments: [
        (true, true, true, true), (false, true, true, false), (true, false, true, false), (true, true, false, false),
    ])
    func samplesOnlyWhenEnabledVisibleAndAwake(enabled: Bool, panel: Bool, ambient: Bool, expected: Bool) {
        #expect(SystemSampling.shouldSample(isEnabled: enabled, isPanelVisible: panel, ambientVisible: ambient) == expected)
    }
}
