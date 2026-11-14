//
//  SystemMonitorSettingsTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

@MainActor
struct SystemMonitorSettingsTests {
    let defaults: UserDefaults

    init() {
        let suite = "thenotchTests.SystemMonitorSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaults_areCPUMemoryEveryTwoSeconds() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.systemMonitorMetrics == [.cpu, .memory])
        #expect(settings.systemMonitorInterval == .two)
    }

    @Test func metricsPersistAsRawValues() {
        let settings = AppSettings(defaults: defaults)
        settings.systemMonitorMetrics = [.network, .cpu]
        #expect(defaults.stringArray(forKey: "systemMonitor.menuBarMetrics") == ["cpu", "network"])
        #expect(AppSettings(defaults: defaults).systemMonitorMetrics == [.cpu, .network])
    }

    @Test func emptyMetricSelectionPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.systemMonitorMetrics = []
        #expect(AppSettings(defaults: defaults).systemMonitorMetrics.isEmpty)
    }

    @Test func unknownStoredMetricsAreIgnored() {
        defaults.set(["memory", "bogus", "gpu"], forKey: "systemMonitor.menuBarMetrics")
        #expect(AppSettings(defaults: defaults).systemMonitorMetrics == [.memory])
    }

    @Test(arguments: SystemMonitorInterval.allCases)
    func intervalPersists(interval: SystemMonitorInterval) {
        let settings = AppSettings(defaults: defaults)
        settings.systemMonitorInterval = interval
        #expect(defaults.integer(forKey: "systemMonitor.interval") == interval.rawValue)
        #expect(AppSettings(defaults: defaults).systemMonitorInterval == interval)
    }

    @Test(arguments: [0, 3, -1, 60])
    func invalidStoredIntervalFallsBackToDefault(value: Int) {
        defaults.set(value, forKey: "systemMonitor.interval")
        #expect(AppSettings(defaults: defaults).systemMonitorInterval == .two)
    }

    @Test func toolKindAndPaneRoundTrip() {
        #expect(ToolKind.systemMonitor.rawValue == "systemMonitor")
        #expect(ToolKind.systemMonitor.id == "systemMonitor")
        #expect(SettingsPane(storedValue: "tool.systemMonitor") == .tool(.systemMonitor))
        #expect(SettingsPane.tool(.systemMonitor).storedValue == "tool.systemMonitor")
    }
}
