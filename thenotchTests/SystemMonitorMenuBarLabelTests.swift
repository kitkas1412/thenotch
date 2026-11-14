//
//  SystemMonitorMenuBarLabelTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct SystemMonitorMenuBarLabelTests {
    private let fs = "\u{2007}"

    private func snapshot(cpu: Double = 0.12, memory: Double = 0.63,
                          down: Double = 1_200_000, up: Double = 512) -> SystemSnapshot {
        SystemSnapshot(cpu: cpu,
                       memory: MemoryUsage(used: UInt64(memory * 1000), total: 1000),
                       networkDown: down, networkUp: up)
    }

    @Test func titleUsesFixedOrderRegardlessOfSelection() {
        let all = SystemMonitorMenuBarLabel.title(snapshot: snapshot(), metrics: [.network, .memory, .cpu]).string
        let cpu = all.range(of: "CPU")!, mem = all.range(of: "MEM")!, down = all.range(of: "↓")!
        #expect(cpu.lowerBound < mem.lowerBound)
        #expect(mem.lowerBound < down.lowerBound)
        #expect(all.contains("12%"))
        #expect(all.contains("63%"))
        #expect(all.contains("1.2 MB/s"))
        #expect(all.contains("512 B/s"))
    }

    @Test func titleShowsOnlySelectedMetrics() {
        let text = SystemMonitorMenuBarLabel.title(snapshot: snapshot(), metrics: [.memory]).string
        #expect(text.contains("MEM"))
        #expect(!text.contains("CPU"))
        #expect(!text.contains("↓"))
    }

    @Test func titleIsEmptyWithoutMetrics() {
        #expect(SystemMonitorMenuBarLabel.title(snapshot: snapshot(), metrics: []).length == 0)
    }

    @Test func titleLengthIsStableAcrossValues() {
        let metrics: Set<SystemMetric> = [.cpu, .memory, .network]
        let small = SystemMonitorMenuBarLabel.title(
            snapshot: snapshot(cpu: 0.05, memory: 0.0, down: 0, up: 0), metrics: metrics)
        let large = SystemMonitorMenuBarLabel.title(
            snapshot: snapshot(cpu: 1.0, memory: 1.0, down: 999_000, up: 999_000), metrics: metrics)
        #expect(small.length == large.length)
        #expect(small.string.contains(fs))
    }

    @Test func percentIsPaddedWithFigureSpaces() {
        let text = SystemMonitorMenuBarLabel.title(snapshot: snapshot(cpu: 0.05), metrics: [.cpu]).string
        #expect(text == "CPU \(fs)\(fs)5%")
    }

    @Test func accessibilityLabelListsSelectedMetricsInOrder() {
        let label = SystemMonitorMenuBarLabel.accessibilityLabel(
            snapshot: snapshot(), metrics: [.network, .cpu, .memory])
        #expect(label == "System Monitor: CPU 12 percent, Memory 63 percent, "
                + "Network download 1.2 MB/s, upload 512 B/s")
    }

    @Test func accessibilityLabelWithoutMetricsIsTheToolName() {
        #expect(SystemMonitorMenuBarLabel.accessibilityLabel(snapshot: snapshot(), metrics: []) == "System Monitor")
    }
}
