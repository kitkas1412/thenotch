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

    @Test func toolKindAndPaneRoundTrip() {
        #expect(ToolKind.systemMonitor.rawValue == "systemMonitor")
        #expect(ToolKind.systemMonitor.id == "systemMonitor")
        #expect(SettingsPane(storedValue: "tool.systemMonitor") == .tool(.systemMonitor))
        #expect(SettingsPane.tool(.systemMonitor).storedValue == "tool.systemMonitor")
    }
}
