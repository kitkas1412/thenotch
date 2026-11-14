//
//  ShortcutTests.swift
//  thenotchTests
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import thenotch

struct ShortcutTests {
    private func shortcut(_ key: Int, _ modifiers: Shortcut.Modifiers) -> Shortcut {
        Shortcut(keyCode: UInt32(key), modifiers: modifiers)
    }

    // MARK: Modifiers

    @Test func modifiersIgnoreCapsLockAndFunctionFlags() {
        let flags: NSEvent.ModifierFlags = [.command, .capsLock, .function, .numericPad]
        #expect(Shortcut.Modifiers(flags) == [.command])
    }

    @Test func modifiersMapEveryRelevantFlag() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        #expect(Shortcut.Modifiers(flags) == [.command, .option, .control, .shift])
    }

    @Test func carbonFlagsCombineModifiers() {
        let all: Shortcut.Modifiers = [.command, .option, .control, .shift]
        #expect(all.carbonFlags == UInt32(cmdKey | optionKey | controlKey | shiftKey))
        #expect(Shortcut.Modifiers([]).carbonFlags == 0)
        #expect(shortcut(kVK_ANSI_A, [.control, .shift]).carbonModifiers == UInt32(controlKey | shiftKey))
    }

    @Test func eventInitializerUsesKeyCodeAndFlags() {
        let s = Shortcut(keyCode: UInt16(kVK_Space), flags: [.control, .option])
        #expect(s == shortcut(kVK_Space, [.control, .option]))
    }

    // MARK: Validation

    @Test func functionKeysAreValidAlone() {
        let f5 = shortcut(kVK_F5, [])
        #expect(f5.isFunctionKey)
        #expect(f5.validation == .valid)
    }

    @Test func plainLettersNeedCommandOrControl() {
        #expect(shortcut(kVK_ANSI_A, []).validation == .needsCommandOrControl)
        #expect(shortcut(kVK_ANSI_A, [.option, .shift]).validation == .needsCommandOrControl)
        #expect(!shortcut(kVK_ANSI_A, []).isFunctionKey)
    }

    @Test func commandOrControlMakesLettersValid() {
        #expect(shortcut(kVK_ANSI_A, .command).validation == .valid)
        #expect(shortcut(kVK_ANSI_A, .control).validation == .valid)
        #expect(shortcut(kVK_Space, [.control, .option]).validation == .valid)
    }

    @Test func systemShortcutsAreReserved() {
        let cases: [(Int, Shortcut.Modifiers, String)] = [
        (kVK_Space, .command, "Spotlight"),
        (kVK_Space, .control, "Input sources"),
        (kVK_Tab, .command, "App switcher"),
        (kVK_ANSI_Grave, .command, "Window switcher"),
        (kVK_ANSI_Q, .command, "Quit"),
        (kVK_ANSI_W, .command, "Close window"),
        (kVK_ANSI_H, .command, "Hide app"),
        (kVK_ANSI_M, .command, "Minimize"),
        (kVK_ANSI_Comma, .command, "Settings"),
        (kVK_ANSI_3, [.command, .shift], "Screenshot"),
        (kVK_ANSI_4, [.command, .shift], "Screenshot"),
        (kVK_ANSI_5, [.command, .shift], "Screenshot"),
        (kVK_UpArrow, .control, "Mission Control"),
        (kVK_DownArrow, .control, "Application windows"),
        (kVK_LeftArrow, .control, "Move to the left Space"),
        (kVK_RightArrow, .control, "Move to the right Space"),
        ]
        for (key, modifiers, name) in cases {
            #expect(shortcut(key, modifiers).validation == .reservedBySystem(name))
        }
    }

    @Test func reservedMatchIsExactCombination() {
        // Extra modifier: no longer the system shortcut.
        #expect(shortcut(kVK_Space, [.command, .option]).validation == .valid)
        #expect(shortcut(kVK_ANSI_Q, [.command, .shift]).validation == .valid)
        #expect(shortcut(kVK_ANSI_3, .command).validation == .valid)
        #expect(shortcut(kVK_UpArrow, [.control, .shift]).validation == .valid)
    }

    // MARK: Display

    @Test func displayStringUsesMacOSModifierOrder() {
        let s = shortcut(kVK_Space, [.command, .shift, .option, .control])
        #expect(s.displayString == "⌃⌥⇧⌘Space")
        #expect(shortcut(kVK_ANSI_K, [.command]).displayString == "⌘K")
        #expect(shortcut(kVK_F12, []).displayString == "F12")
    }

    @Test func keyNameCoversTablesAndFallsBack() {
        #expect(Shortcut.keyName(UInt32(kVK_ANSI_Z)) == "Z")
        #expect(Shortcut.keyName(UInt32(kVK_LeftArrow)) == "←")
        #expect(Shortcut.keyName(UInt32(kVK_F20)) == "F20")
        #expect(Shortcut.keyName(999) == "Key 999")
    }

    // MARK: Codable

    @Test func codableRoundTrips() throws {
        let original = shortcut(kVK_ANSI_J, [.control, .option])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == original)
    }

    // MARK: Actions

    @Test func actionIDsAreUniqueAndIncludeNotchToggle() {
        let ids = ShortcutAction.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(ShortcutAction.notchToggle.id))
        #expect(ShortcutAction.notchToggle.id == "notch.toggle")
    }
}
