//
//  ClipboardSettingsTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

@MainActor
struct ClipboardSettingsTests {
    let defaults: UserDefaults

    init() {
        let suite = "thenotchTests.ClipboardSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaultValues() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.clipboardLimit == 200)
        #expect(!settings.clipboardClearOnQuit)
        #expect(settings.clipboardIgnoredApps.isEmpty)
        #expect(settings.clipboardPastesDirectly)
        #expect(settings.clipboardRecordsRemote)
        #expect(AppSettings.clipboardLimits == [50, 100, 200, 500])
    }

    @Test(arguments: [50, 100, 200, 500])
    func validLimitIsKept(limit: Int) {
        defaults.set(limit, forKey: "clipboard.limit")
        #expect(AppSettings(defaults: defaults).clipboardLimit == limit)
    }

    @Test(arguments: [0, -1, 75, 1000])
    func invalidLimitFallsBackTo200(limit: Int) {
        defaults.set(limit, forKey: "clipboard.limit")
        #expect(AppSettings(defaults: defaults).clipboardLimit == 200)
    }

    @Test func changesPersistUnderTheirKeys() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardLimit = 50
        settings.clipboardClearOnQuit = true
        settings.clipboardIgnoredApps = ["com.example.a"]
        settings.clipboardPastesDirectly = false
        settings.clipboardRecordsRemote = false
        #expect(defaults.integer(forKey: "clipboard.limit") == 50)
        #expect(defaults.bool(forKey: "clipboard.clearOnQuit"))
        #expect(defaults.stringArray(forKey: "clipboard.ignoredApps") == ["com.example.a"])
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.clipboardLimit == 50)
        #expect(reloaded.clipboardClearOnQuit)
        #expect(reloaded.clipboardIgnoredApps == ["com.example.a"])
        #expect(!reloaded.clipboardPastesDirectly)
        #expect(!reloaded.clipboardRecordsRemote)
    }

    @Test func showHistoryShortcutDefaultIsValidAndUnique() throws {
        let action = ShortcutAction.clipboardShowHistory
        #expect(action.id == "clipboard.showHistory")
        #expect(action.tool == .clipboard)
        let shortcut = try #require(action.defaultShortcut)
        #expect(shortcut.modifiers == [.control, .command])
        #expect(shortcut.validation == .valid)
        #expect(ShortcutAction.all.contains(action))
        let others = ShortcutAction.all.filter { $0.id != action.id }.compactMap(\.defaultShortcut)
        #expect(!others.contains(shortcut))
        let all = ShortcutAction.all.compactMap(\.defaultShortcut)
        #expect(Set(all).count == all.count)
    }

    @Test func historySearchMatchesTextAndFileNamesOnly() {
        let text = ClipboardFixtures.textItem("Hello World")
        let files = ClipboardItem(createdAt: .now, content: .files(["/Users/x/Report.PDF"]), sourceBundleID: nil, contentHash: "f")
        let image = ClipboardFixtures.imageItem(bytes: 1)
        #expect(ClipboardHistoryModel.matches(text, "world"))
        #expect(!ClipboardHistoryModel.matches(text, "xyz"))
        #expect(ClipboardHistoryModel.matches(files, "report"))
        #expect(!ClipboardHistoryModel.matches(files, "users"))
        #expect(!ClipboardHistoryModel.matches(image, "png"))
    }

    @Test func historySearchLooksAtTheStartOfLongTextOnly() {
        let limit = ClipboardHistoryModel.searchedCharacters
        let long = ClipboardFixtures.textItem(String(repeating: "a", count: limit - 6) + "needle" + "haystack")
        #expect(ClipboardHistoryModel.matches(long, "needle"))
        #expect(!ClipboardHistoryModel.matches(long, "haystack"))
    }

    @Test func quickNumbersFollowTheDigitKeys() {
        #expect(ClipboardHistoryModel.quickNumber(keyCode: 0x12) == 1) // kVK_ANSI_1
        #expect(ClipboardHistoryModel.quickNumber(keyCode: 0x17) == 5) // kVK_ANSI_5
        #expect(ClipboardHistoryModel.quickNumber(keyCode: 0x16) == 6) // kVK_ANSI_6
        #expect(ClipboardHistoryModel.quickNumber(keyCode: 0x19) == 9) // kVK_ANSI_9
        #expect(ClipboardHistoryModel.quickNumber(keyCode: 0x1D) == nil) // kVK_ANSI_0
        #expect(ClipboardHistoryModel.quickNumber(keyCode: 0x53) == nil) // keypad 1
    }

    @Test func pasteIsSentOnlyToTheTargetInFrontWithoutSecureInput() {
        #expect(ClipboardPaster.maySendPaste(targetPID: 42, frontmostPID: 42, secureInput: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: nil, frontmostPID: 42, secureInput: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: nil, frontmostPID: nil, secureInput: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: 42, frontmostPID: 7, secureInput: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: 42, frontmostPID: 42, secureInput: true))
    }

    @Test func storageIssuesHaveMessages() {
        let issues: [ClipboardStore.StorageIssue] = [.keyUnavailable, .startedFresh, .notDeleted, .notDeletedKeyUnavailable]
        #expect(Set(issues.map(\.message)).count == issues.count)
        #expect(ClipboardTool.ClearResult.cleared.problem == nil)
        #expect(ClipboardTool.ClearResult.filesNotDeleted.problem != nil)
        #expect(ClipboardTool.ClearResult.keyNotDeleted.problem != nil)
    }
}
