//
//  IslandStateTests.swift
//  thenotchTests
//

import CoreGraphics
import SwiftUI
import Testing
@testable import thenotch

/// Stand-in module whose content and height the tests control.
@MainActor
private final class FakeModule: IslandModule {
    let id: String
    var hasExpandedContent: Bool
    var expandedContentHeight: CGFloat
    var expandedWidth: CGFloat

    init(_ id: String, content: Bool = false, height: CGFloat = IslandState.defaultContentHeight, width: CGFloat = IslandState.expandedWidth) {
        self.id = id
        hasExpandedContent = content
        expandedContentHeight = height
        expandedWidth = width
    }

    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct IslandStateTests {
    let state = IslandState()
    private let music = FakeModule("music")
    private let battery = FakeModule("battery")
    private let shelf = FakeModule("shelf")

    init() {
        state.notchSize = CGSize(width: 188, height: 32)
        state.modules = [music, battery, shelf]
    }

    @Test func nothingToShowMeansNoExpandedModule() {
        #expect(state.currentModule == nil)
        #expect(state.compactSize == state.notchSize)
        #expect(state.expandedModule == nil)
    }

    @Test func firstModuleWithContentIsShown() {
        shelf.hasExpandedContent = true
        #expect(state.expandedModule?.id == "shelf")
        music.hasExpandedContent = true
        #expect(state.expandedModule?.id == "music")
    }

    @Test func activityAddsWingsAndPicksItsModule() {
        music.hasExpandedContent = true
        battery.hasExpandedContent = true
        state.activities.publish(LiveActivity(id: "peek", moduleID: "battery", priority: 50))
        #expect(state.currentModule?.id == "battery")
        // 20 pt content with (32 − 20) / 2 = 6 pt padding on each side.
        #expect(state.compactPadding == 6)
        #expect(state.compactSize == CGSize(width: 188 + (20 + 12) * 2, height: 32))
        #expect(state.expandedModule?.id == "battery")
    }

    @Test func activityWithoutContentFallsBackToAModuleWithContent() {
        shelf.hasExpandedContent = true
        state.activities.publish(LiveActivity(id: "music", moduleID: "music", priority: 10))
        #expect(state.expandedModule?.id == "shelf")
    }

    @Test func pinnedModuleWinsEvenWithoutContent() {
        music.hasExpandedContent = true
        state.pinnedModuleID = "shelf"
        #expect(state.expandedModule?.id == "shelf")
    }

    @Test func pinnedModuleThatWasDisabledIsIgnored() {
        music.hasExpandedContent = true
        state.pinnedModuleID = "removed"
        #expect(state.expandedModule?.id == "music")
    }

    @Test func tabsShowOnlyWhenSeveralModulesHaveContent() {
        #expect(!state.showsTabs)
        music.hasExpandedContent = true
        #expect(!state.showsTabs)
        shelf.hasExpandedContent = true
        #expect(state.showsTabs)
        #expect(state.tabModules.map(\.id) == ["music", "shelf"])
    }

    @Test func noTabsWhileFilesAreDraggedIn() {
        music.hasExpandedContent = true
        shelf.hasExpandedContent = true
        state.isDraggingFiles = true
        #expect(!state.showsTabs)
    }

    @Test func selectingATabShowsThatModule() {
        music.hasExpandedContent = true
        shelf.hasExpandedContent = true
        state.activities.publish(LiveActivity(id: "song", moduleID: "music", priority: 10))
        #expect(state.expandedModule?.id == "music")
        state.select("shelf")
        #expect(state.expandedModule?.id == "shelf")
    }

    @Test func expandedHeightFollowsTheShownModule() {
        state.notchSize = CGSize(width: 190, height: 32)
        let below = 32 + IslandStyle.Spacing.content
        #expect(state.expandedSize == CGSize(width: IslandState.expandedWidth, height: below + IslandState.defaultContentHeight))
        let player = FakeModule("player", content: true, height: 156)
        state.modules = [player]
        #expect(state.expandedSize.height == below + 156)
    }

    /// The tallest module still fits the panel under a tall notch.
    @Test func tallestContentFitsThePanelUnderATallNotch() {
        state.notchSize = CGSize(width: 190, height: 38)
        state.modules = [FakeModule("player", content: true, height: 156)]
        #expect(state.expandedSize.height <= IslandController.panelSize.height)
    }

    @Test func expandedWidthFollowsTheShownModule() {
        let stack = FakeModule("stack", content: true, width: 256)
        state.modules = [stack]
        #expect(state.expandedSize.width == 256)
    }

    @Test func tabsSitBesideTheNotchOnAWideIsland() {
        music.hasExpandedContent = true
        shelf.hasExpandedContent = true
        state.select("music")
        #expect(state.tabsBesideNotch)
        #expect(state.expandedContentTop == 32 + IslandStyle.Spacing.content)
    }

    @Test func tabsTakeARowUnderTheNotchOnANarrowIsland() {
        let player = FakeModule("player", content: true)
        let stack = FakeModule("stack", content: true, height: 100, width: 256)
        state.modules = [player, stack]
        state.select("stack")
        #expect(!state.tabsBesideNotch)
        let top = 32 + IslandStyle.Spacing.content + IslandState.tabRowHeight
        #expect(state.expandedContentTop == top)
        #expect(state.expandedSize == CGSize(width: 256, height: top + 100))
        // No row without tabs.
        player.hasExpandedContent = false
        #expect(state.expandedContentTop == 32 + IslandStyle.Spacing.content)
    }

    /// The shelf's stack, with its tab row, fits the panel under a tall notch.
    @Test func shelfStackWithTabsFitsThePanel() {
        state.notchSize = CGSize(width: 200, height: 38)
        let player = FakeModule("player", content: true, height: 156)
        let stack = FakeModule("stack", content: true, height: ShelfStackView.contentHeight, width: ShelfStackView.islandWidth)
        state.modules = [player, stack]
        state.select("stack")
        #expect(state.expandedSize.height <= IslandController.panelSize.height)
        #expect(state.expandedSize.width <= IslandController.panelSize.width)
    }
}

struct AmbientConditionsTests {
    @Test func animatesOnlyWhenSeenAndNotSavingPower() {
        #expect(AmbientConditions().allowsAnimation)
        #expect(!AmbientConditions(isDisplayAsleep: true).allowsAnimation)
        #expect(!AmbientConditions(isScreenLocked: true).allowsAnimation)
        #expect(!AmbientConditions(isSessionInactive: true).allowsAnimation)
        #expect(!AmbientConditions(isLowPowerMode: true).allowsAnimation)
    }
}
