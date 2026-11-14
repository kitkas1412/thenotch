//
//  ShortcutSettingsTests.swift
//  thenotchTests
//

import Carbon.HIToolbox
import Foundation
import Testing
@testable import thenotch

@MainActor
struct ShortcutSettingsTests {
    let defaults: UserDefaults
    let id = ShortcutAction.notchToggle.id
    let sample = Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .option])

    init() {
        let suite = "thenotchTests.ShortcutSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func noShortcutByDefault() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.shortcut(for: id) == nil)
        #expect(settings.shortcuts[id] == nil)
    }

    @Test func settingStoresJSONUnderPrefixedKey() throws {
        let settings = AppSettings(defaults: defaults)
        settings.setShortcut(sample, for: id)
        #expect(settings.shortcut(for: id) == sample)
        let data = try #require(defaults.data(forKey: "shortcut.\(id)"))
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == sample)
    }

    @Test func shortcutPersistsAcrossInstances() {
        AppSettings(defaults: defaults).setShortcut(sample, for: id)
        #expect(AppSettings(defaults: defaults).shortcut(for: id) == sample)
    }

    @Test func nilRemovesTheKeyAndPersists() {
        // Notch has no default, so clearing removes the key.
        let settings = AppSettings(defaults: defaults)
        settings.setShortcut(sample, for: id)
        settings.setShortcut(nil, for: id)
        #expect(settings.shortcut(for: id) == nil)
        #expect(defaults.object(forKey: "shortcut.\(id)") == nil)
        #expect(AppSettings(defaults: defaults).shortcut(for: id) == nil)
    }

    @Test func changeCallbackFiresOnceWithActionIDOnRealChange() {
        let settings = AppSettings(defaults: defaults)
        var fired: [String] = []
        let token = settings.observeShortcuts { fired.append($0) }
        defer { token.cancel() }
        settings.setShortcut(sample, for: id)
        settings.setShortcut(sample, for: id)
        #expect(fired == [id])
        settings.setShortcut(nil, for: id)
        #expect(fired == [id, id])
    }

    @Test func clearingAnUnsetShortcutDoesNotFire() {
        let settings = AppSettings(defaults: defaults)
        var count = 0
        let token = settings.observeShortcuts { _ in count += 1 }
        defer { token.cancel() }
        settings.setShortcut(nil, for: id)
        #expect(count == 0)
    }

    @Test func shortcutsDoNotTouchOtherSettings() {
        let settings = AppSettings(defaults: defaults)
        settings.setEnabled(.hud, true)
        let before = settings.enabledModules
        settings.setShortcut(sample, for: id)
        #expect(settings.enabledModules == before)
        #expect(AppSettings(defaults: defaults).enabledModules == before)
    }

    @Test func corruptStoredDataIsIgnored() {
        defaults.set(Data("not json".utf8), forKey: "shortcut.\(id)")
        #expect(AppSettings(defaults: defaults).shortcut(for: id) == nil)
    }

    // MARK: Defaults

    @Test func windowDefaultsAreValidAndUnique() {
        let actions = ShortcutAction.actions(for: .windowManagement)
        #expect(actions.count == WindowAction.allCases.count)
        let shortcuts = actions.compactMap(\.defaultShortcut)
        #expect(shortcuts.count == actions.count)
        #expect(Set(shortcuts).count == shortcuts.count)
        for shortcut in shortcuts { #expect(shortcut.validation == .valid) }
    }

    @Test func defaultAppliesUntilClearedAndResetRestoresIt() {
        let leftHalf = ShortcutAction.windowActionID(.leftHalf)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.shortcut(for: leftHalf) == WindowAction.leftHalf.defaultShortcut)
        settings.setShortcut(nil, for: leftHalf)
        #expect(settings.shortcut(for: leftHalf) == nil)
        #expect(AppSettings(defaults: defaults).shortcut(for: leftHalf) == nil)
        settings.resetShortcut(for: leftHalf)
        #expect(settings.shortcut(for: leftHalf) == WindowAction.leftHalf.defaultShortcut)
        #expect(AppSettings(defaults: defaults).shortcut(for: leftHalf) == WindowAction.leftHalf.defaultShortcut)
    }

    @Test func cancelledObservationStopsFiring() {
        let settings = AppSettings(defaults: defaults)
        var count = 0
        let token = settings.observeShortcuts { _ in count += 1 }
        settings.setShortcut(sample, for: id)
        token.cancel()
        settings.setShortcut(nil, for: id)
        #expect(count == 1)
    }

    @Test func everySubscriberIsNotified() {
        let settings = AppSettings(defaults: defaults)
        var first: [String] = [], second: [String] = []
        let a = settings.observeShortcuts { first.append($0) }
        let b = settings.observeShortcuts { second.append($0) }
        settings.setShortcut(sample, for: id)
        #expect(first == [id] && second == [id])
        withExtendedLifetime((a, b)) {}
    }

    @Test func droppedObservationStopsFiring() {
        let settings = AppSettings(defaults: defaults)
        var count = 0
        var token: ShortcutObservation? = settings.observeShortcuts { _ in count += 1 }
        settings.setShortcut(sample, for: id)
        token = nil
        settings.setShortcut(nil, for: id)
        #expect(count == 1)
        _ = token
    }

    @Test func resetWithoutDefaultClearsTheBinding() {
        let settings = AppSettings(defaults: defaults)
        settings.setShortcut(sample, for: id)
        settings.resetShortcut(for: id)
        #expect(settings.shortcut(for: id) == nil)
        #expect(AppSettings(defaults: defaults).shortcut(for: id) == nil)
    }

    @Test func clearingAWindowActionPersistsAcrossInstances() {
        let action = ShortcutAction.windowActionID(.maximize)
        let settings = AppSettings(defaults: defaults)
        settings.setShortcut(nil, for: action)
        #expect(defaults.data(forKey: "shortcut.\(action)") == Data("null".utf8))
        #expect(AppSettings(defaults: defaults).shortcut(for: action) == nil)
    }
}
