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

    @Test func modulesAreEnabledByDefaultExceptTheHUD() {
        // The HUD needs Accessibility access, asked for when it's turned on.
        #expect(AppSettings(defaults: defaults).enabledModules == [.nowPlaying, .battery, .shelf])
    }

    @Test func enablingTheHUDPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.setEnabled(.hud, true)
        #expect(AppSettings(defaults: defaults).enabledModules == ModuleKind.allCases)
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
}
