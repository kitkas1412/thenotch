//
//  ShortcutCaptureTests.swift
//  thenotchTests
//

import AppKit
import Carbon.HIToolbox
import Testing
@testable import thenotch

@MainActor
struct ShortcutCaptureTests {
    private func key(_ code: Int) -> UInt16 { UInt16(code) }

    // MARK: interpret

    @Test func escapeAloneCancels() {
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Escape), flags: []) == .cancel)
    }

    @Test func deleteKeysAloneClear() {
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Delete), flags: []) == .clear)
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_ForwardDelete), flags: []) == .clear)
    }

    @Test func irrelevantFlagsDoNotPreventCancelOrClear() {
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Escape), flags: [.capsLock]) == .cancel)
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Delete), flags: [.function]) == .clear)
    }

    @Test func escapeAndDeleteWithModifiersAreCandidates() {
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Escape), flags: [.command])
            == .candidate(Shortcut(keyCode: UInt32(kVK_Escape), modifiers: .command)))
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Delete), flags: [.control])
            == .candidate(Shortcut(keyCode: UInt32(kVK_Delete), modifiers: .control)))
    }

    @Test func otherKeysAreCandidates() {
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_ANSI_A), flags: [])
            == .candidate(Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: [])))
        #expect(ShortcutCapture.interpret(keyCode: key(kVK_Space), flags: [.control, .option])
            == .candidate(Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .option])))
    }

    // MARK: problem

    private func problem(_ shortcut: Shortcut, center: HotKeyCenter? = nil) -> String? {
        ShortcutCapture.problem(for: shortcut, actionID: "other.action", hotKeys: center ?? HotKeyCenter())
    }

    @Test func problemForMissingCommandOrControl() {
        #expect(problem(Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: .shift)) == "Use ⌘ or ⌃ with the key")
    }

    @Test func problemForSystemShortcutNamesIt() {
        #expect(problem(Shortcut(keyCode: UInt32(kVK_Space), modifiers: .command)) == "Used by macOS (Spotlight)")
    }

    @Test func noProblemForFreeValidShortcut() {
        #expect(problem(Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option])) == nil)
    }

    @Test func problemForShortcutUsedByAnotherAction() {
        let center = HotKeyCenter()
        center.suspend() // bookkeeping only: nothing reaches Carbon
        let used = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option])
        center.register(id: ShortcutAction.notchToggle.id, shortcut: used) {}
        #expect(ShortcutCapture.problem(for: used, actionID: "other.action", hotKeys: center)
            == "Already used by Open or close the island")
        // The action's own shortcut is not a conflict.
        #expect(ShortcutCapture.problem(for: used, actionID: ShortcutAction.notchToggle.id, hotKeys: center) == nil)
    }

    @Test func conflictOfUnknownActionUsesGenericTitle() {
        let center = HotKeyCenter()
        center.suspend()
        let used = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: .control)
        center.register(id: "ghost.action", shortcut: used) {}
        #expect(problem(used, center: center) == "Already used by another shortcut")
    }
}
