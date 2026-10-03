//
//  IslandStateTests.swift
//  thenotchTests
//

import CoreGraphics
import Testing
@testable import thenotch

@MainActor
struct IslandStateTests {
    let state: IslandState

    init() {
        state = IslandState()
        state.notchSize = CGSize(width: 188, height: 32)
        // Modules are only constructed, not started.
        state.modules = ModuleKind.allCases.map { $0.makeModule(activities: state.activities) }
    }

    @Test func compactIsNotchSizedWithoutActivity() {
        #expect(state.currentModule == nil)
        #expect(state.compactSize == state.notchSize)
        #expect(state.expandedModule?.id == ModuleKind.nowPlaying.id)
    }

    @Test func activityAddsWingsAndPicksModule() {
        state.activities.publish(LiveActivity(id: "peek", moduleID: ModuleKind.battery.id, priority: 50))
        #expect(state.currentModule?.id == ModuleKind.battery.id)
        #expect(state.compactSize == CGSize(width: 188 + 120, height: 32))
        #expect(state.expandedModule?.id == ModuleKind.battery.id)
    }

    @Test func pinnedModuleWinsOverNewActivity() {
        state.pinnedModuleID = ModuleKind.nowPlaying.id
        state.activities.publish(LiveActivity(id: "peek", moduleID: ModuleKind.battery.id, priority: 50))
        #expect(state.expandedModule?.id == ModuleKind.nowPlaying.id)
    }

    @Test func pinnedModuleThatWasDisabledIsIgnored() {
        state.pinnedModuleID = "removed"
        #expect(state.expandedModule?.id == ModuleKind.nowPlaying.id)
    }
}
