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
    var expandedHeight: CGFloat

    init(_ id: String, content: Bool = false, height: CGFloat = IslandState.defaultExpandedHeight) {
        self.id = id
        hasExpandedContent = content
        expandedHeight = height
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
        #expect(state.compactSize == CGSize(width: 188 + 120, height: 32))
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

    @Test func expandedHeightFollowsTheShownModule() {
        #expect(state.expandedSize == CGSize(width: IslandState.expandedWidth, height: IslandState.defaultExpandedHeight))
        let player = FakeModule("player", content: true, height: 206)
        state.modules = [player]
        #expect(state.expandedSize.height == 206)
        #expect(state.expandedSize.height <= IslandController.panelSize.height)
    }
}
