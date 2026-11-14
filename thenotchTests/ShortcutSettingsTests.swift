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
        #expect(settings.shortcuts.isEmpty)
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
        settings.onShortcutsChange = { fired.append($0) }
        settings.setShortcut(sample, for: id)
        settings.setShortcut(sample, for: id)
        #expect(fired == [id])
        settings.setShortcut(nil, for: id)
        #expect(fired == [id, id])
    }

    @Test func clearingAnUnsetShortcutDoesNotFire() {
        let settings = AppSettings(defaults: defaults)
        var count = 0
        settings.onShortcutsChange = { _ in count += 1 }
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
}
