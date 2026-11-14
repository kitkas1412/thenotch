//
//  AppSettingsTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

@MainActor
struct AppSettingsTests {
    let defaults: UserDefaults

    init() {
        let suite = "thenotchTests.AppSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func modulesNeedingAPermissionAreOffByDefault() {
        // Asked for when they're turned on: Accessibility, Bluetooth.
        #expect(AppSettings(defaults: defaults).enabledModules == [.nowPlaying, .battery, .shelf])
    }

    @Test func enablingTheHUDPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.setEnabled(.hud, true)
        #expect(AppSettings(defaults: defaults).enabledModules == [.nowPlaying, .battery, .shelf, .hud])
    }

    @Test func disablingAModulePersists() {
        let settings = AppSettings(defaults: defaults)
        settings.setEnabled(.nowPlaying, false)
        #expect(settings.enabledModules == [.battery, .shelf])
        #expect(AppSettings(defaults: defaults).enabledModules == [.battery, .shelf])
    }

    @Test func reEnablingKeepsCanonicalOrder() {
        let settings = AppSettings(defaults: defaults)
        settings.setEnabled(.nowPlaying, false)
        settings.setEnabled(.nowPlaying, true)
        #expect(settings.enabledModules == [.nowPlaying, .battery, .shelf])
    }

    @Test func changeCallbackFiresOnlyOnActualChange() {
        let settings = AppSettings(defaults: defaults)
        var calls = 0
        settings.onModulesChange = { calls += 1 }
        settings.setEnabled(.battery, true)  // already on
        settings.setEnabled(.battery, false)
        #expect(calls == 1)
    }

    @Test func moduleKindsMatchModuleIDs() {
        let activities = ActivityCenter()
        let settings = AppSettings(defaults: defaults)
        for kind in ModuleKind.allCases {
            #expect(kind.makeModule(activities: activities, settings: settings).id == kind.id)
        }
    }

    @Test func shelfLifetimeDefaultsToADayAndPersists() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.shelfLifetime == .day)
        settings.shelfLifetime = .forever
        #expect(AppSettings(defaults: defaults).shelfLifetime == .forever)
    }

    // MARK: Tools

    @Test func toolsFollowTheirDefaultAndDoNotTouchModules() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.enabledTools == ToolKind.allCases.filter(\.isOnByDefault))
        #expect(settings.isToolEnabled(.notch) == ToolKind.notch.isOnByDefault)
        settings.setToolEnabled(.notch, false)
        #expect(settings.enabledModules == [.nowPlaying, .battery, .shelf])
        #expect(defaults.object(forKey: "module.nowPlaying.enabled") == nil)
    }

    @Test func toolEnabledPersistsUnderItsKey() {
        let settings = AppSettings(defaults: defaults)
        settings.setToolEnabled(.notch, false)
        #expect(settings.enabledTools.isEmpty)
        #expect(defaults.object(forKey: "tool.notch.enabled") as? Bool == false)
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.isToolEnabled(.notch))
        reloaded.setToolEnabled(.notch, true)
        #expect(AppSettings(defaults: defaults).enabledTools == [.notch])
    }

    @Test func onToolsChangeFiresOnlyOnRealChange() {
        let settings = AppSettings(defaults: defaults)
        var fired = 0
        settings.onToolsChange = { fired += 1 }
        settings.setToolEnabled(.notch, true)   // already on
        #expect(fired == 0)
        settings.setToolEnabled(.notch, false)
        #expect(fired == 1)
        settings.setToolEnabled(.notch, false)
        #expect(fired == 1)
        settings.setToolEnabled(.notch, true)
        #expect(fired == 2)
    }

    @Test func moduleChangesDoNotFireToolChange() {
        let settings = AppSettings(defaults: defaults)
        var fired = 0
        settings.onToolsChange = { fired += 1 }
        settings.setEnabled(.hud, true)
        #expect(fired == 0)
    }
}
