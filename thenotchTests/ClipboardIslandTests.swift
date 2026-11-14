//
//  ClipboardIslandTests.swift
//  thenotchTests
//

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import thenotch

@MainActor
private final class OtherModule: IslandModule {
    let id = "other"
    var hasExpandedContent = true
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

/// A stand-in with the Clipboard module's size, since its real content needs a
/// loaded store (which would read the Keychain).
@MainActor
private final class SizedModule: IslandModule {
    let id = "clipboard"
    var hasExpandedContent = true
    var expandedWidth: CGFloat { 600 }
    var expandedContentHeight: CGFloat { ClipboardIslandModule.contentHeight }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct ClipboardIslandTests {
    let tool: ClipboardTool
    let contributions = IslandContributions()

    init() {
        let suite = "thenotchTests.ClipboardIsland.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Not started: nothing reads the Keychain or the disk.
        tool = ClipboardTool(settings: AppSettings(defaults: defaults), hotKeys: HotKeyCenter(), contributions: contributions)
    }

    private func key(_ code: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
    }

    // MARK: Module

    @Test func moduleDeclaresItsPresentation() {
        let module = ClipboardIslandModule(tool: tool, contributions: contributions)
        #expect(module.id == ToolKind.clipboard.id)
        #expect(module.expandedWidth == 600)
        #expect(module.expandedContentHeight == 216)
        #expect(module.takesKeyboard)
        #expect(module.excludesFromCapture)
        #expect(module.tabTitle == ToolKind.clipboard.title)
        #expect(module.tabSymbol == ToolKind.clipboard.symbol)
    }

    @Test func moduleHasNoContentBeforeTheStoreIsLoaded() {
        let module = ClipboardIslandModule(tool: tool, contributions: contributions)
        #expect(!tool.store.isLoaded)
        #expect(!module.hasExpandedContent)
    }

    @Test func moduleIgnoresKeysWhenNotOpen() {
        let module = ClipboardIslandModule(tool: tool, contributions: contributions)
        #expect(!module.handleKeyDown(key(kVK_Escape)))
    }

    @Test(arguments: [32, 37, 38, 40] as [CGFloat])
    func worstCaseExpandedSizeFitsThePanel(notchHeight: CGFloat) {
        let state = IslandState()
        state.notchSize = CGSize(width: 188, height: notchHeight)
        state.modules = [OtherModule(), SizedModule()]
        state.pinnedModuleID = "clipboard"
        #expect(state.showsTabs)
        let size = state.expandedSize
        #expect(size.width == 600)
        // Unclamped: the clamp must not be what makes it fit.
        let unclamped = state.expandedContentTop + ClipboardIslandModule.contentHeight
        #expect(unclamped <= IslandController.panelSize.height)
        #expect(size.height == unclamped)
        #expect(size.width <= IslandController.panelSize.width)
    }

    // MARK: History model

    @Test func escapeClearsASearchFirstThenCloses() {
        let model = ClipboardHistoryModel(tool: tool, pointer: nil)
        var closes = 0
        model.onClose = { closes += 1 }
        model.query = "abc"
        #expect(model.handle(key(kVK_Escape)))
        #expect(model.query.isEmpty)
        #expect(closes == 0)
        #expect(model.handle(key(kVK_Escape)))
        #expect(closes == 1)
    }

    @Test func quickNumberMapsTopRowDigits() {
        #expect(ClipboardHistoryModel.quickNumber(keyCode: kVK_ANSI_1) == 1)
        #expect(ClipboardHistoryModel.quickNumber(keyCode: kVK_ANSI_9) == 9)
        #expect(ClipboardHistoryModel.quickNumber(keyCode: kVK_ANSI_0) == nil)
    }

    @Test func plainKeysAreNotHandled() {
        let model = ClipboardHistoryModel(tool: tool, pointer: nil)
        #expect(!model.handle(key(kVK_ANSI_A)))
    }

    // MARK: Paster

    @Test func ownKeyWindowAlwaysBlocksPaste() {
        for secure in [true, false] {
            for targetNil in [true, false] {
                for same in [true, false] {
                    #expect(!ClipboardPaster.maySendPaste(
                        targetPID: targetNil ? nil : 10, frontmostPID: same ? 10 : 11,
                        secureInput: secure, ownWindowIsKey: true))
                }
            }
        }
    }

    @Test func pasteAllowedOnlyForFrontmostTargetWithoutSecureInput() {
        #expect(ClipboardPaster.maySendPaste(targetPID: 10, frontmostPID: 10, secureInput: false, ownWindowIsKey: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: 10, frontmostPID: 11, secureInput: false, ownWindowIsKey: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: 10, frontmostPID: 10, secureInput: true, ownWindowIsKey: false))
        #expect(!ClipboardPaster.maySendPaste(targetPID: nil, frontmostPID: 10, secureInput: false, ownWindowIsKey: false))
    }
}
