//
//  HotKeyCenterTests.swift
//  thenotchTests
//
//  Only paths that never reach Carbon: invalid shortcuts are refused before
//  registering, and a suspended center records registrations without
//  touching the system.
//

import Carbon.HIToolbox
import Testing
@testable import thenotch

@MainActor
struct HotKeyCenterTests {
    private let a = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option])
    private let b = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.control, .option])

    private func suspendedCenter() -> HotKeyCenter {
        let center = HotKeyCenter()
        center.suspend()
        return center
    }

    @Test func invalidShortcutIsRefusedAndRecorded() {
        let center = HotKeyCenter() // not suspended: proves Carbon isn't reached
        let result = center.register(id: "x", shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: []), handler: {})
        #expect(result == .invalid)
        #expect(center.lastResult(for: "x") == .invalid)
        #expect(center.conflictingID(for: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: []), excluding: nil) == nil)
    }

    @Test func reservedShortcutIsInvalid() {
        let center = HotKeyCenter()
        let result = center.register(id: "x", shortcut: Shortcut(keyCode: UInt32(kVK_Space), modifiers: .command), handler: {})
        #expect(result == .invalid)
    }

    @Test func registeringInvalidReplacesEarlierRegistration() {
        let center = suspendedCenter()
        center.register(id: "x", shortcut: a, handler: {})
        center.register(id: "x", shortcut: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: []), handler: {})
        #expect(center.conflictingID(for: a, excluding: nil) == nil)
    }

    @Test func suspendedRegistrationIsRememberedAsRegistered() {
        let center = suspendedCenter()
        #expect(center.isSuspended)
        #expect(center.register(id: "x", shortcut: a, handler: {}) == .registered)
        #expect(center.lastResult(for: "x") == .registered)
    }

    @Test func conflictingIDFindsOtherActionsOnly() {
        let center = suspendedCenter()
        center.register(id: "one", shortcut: a, handler: {})
        center.register(id: "two", shortcut: b, handler: {})
        #expect(center.conflictingID(for: a, excluding: nil) == "one")
        #expect(center.conflictingID(for: a, excluding: "two") == "one")
        #expect(center.conflictingID(for: a, excluding: "one") == nil)
        #expect(center.conflictingID(for: Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: .control), excluding: nil) == nil)
    }

    @Test func unregisterForgetsShortcutAndResult() {
        let center = suspendedCenter()
        center.register(id: "one", shortcut: a, handler: {})
        center.unregister(id: "one")
        #expect(center.lastResult(for: "one") == nil)
        #expect(center.conflictingID(for: a, excluding: nil) == nil)
    }

    @Test func unregisterAllClearsEverything() {
        let center = suspendedCenter()
        center.register(id: "one", shortcut: a, handler: {})
        center.register(id: "two", shortcut: b, handler: {})
        center.unregisterAll()
        #expect(center.results.isEmpty)
        #expect(center.conflictingID(for: b, excluding: nil) == nil)
    }

    @Test func suspendIsIdempotentAndKeepsRegistrations() {
        let center = suspendedCenter()
        center.register(id: "one", shortcut: a, handler: {})
        center.suspend()
        #expect(center.isSuspended)
        #expect(center.conflictingID(for: a, excluding: nil) == "one")
    }

    @Test func resumeWithoutSuspendDoesNothing() {
        let center = HotKeyCenter()
        center.resume()
        #expect(!center.isSuspended)
        #expect(center.results.isEmpty)
    }
}
