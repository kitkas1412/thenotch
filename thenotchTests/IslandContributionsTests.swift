//
//  IslandContributionsTests.swift
//  thenotchTests
//

import SwiftUI
import Testing
@testable import thenotch

@MainActor
private final class FakeContributed: ContributedIslandModule {
    let id: String
    var hasExpandedContent = true
    var expandedContentHeight: CGFloat = IslandState.defaultContentHeight
    var expandedWidth: CGFloat = IslandState.expandedWidth
    private(set) var attached = 0
    private(set) var detached = 0

    init(_ id: String) { self.id = id }

    func start() {}
    func stop() {}
    func attach(activities: ActivityCenter) { attached += 1 }
    func detach() { detached += 1 }
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
private final class FakeHost: IslandHosting {
    var result = true
    private(set) var toggled: [String] = []
    private(set) var closes = 0

    func toggleContribution(id: String) -> Bool {
        toggled.append(id)
        return result
    }

    func closeIsland() { closes += 1 }
}

/// A module that overrides nothing the protocol defaults.
@MainActor
private final class PlainModule: IslandModule {
    let id: String
    var hasExpandedContent = false
    init(_ id: String) { self.id = id }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
struct IslandContributionsTests {
    let contributions = IslandContributions()

    @Test func addAppendsInOrderAndSameIDReplaces() {
        let a = FakeContributed("a"), b = FakeContributed("b"), a2 = FakeContributed("a")
        contributions.add(a)
        contributions.add(b)
        #expect(contributions.modules.map(\.id) == ["a", "b"])
        contributions.add(a2)
        #expect(contributions.modules.count == 2)
        #expect(contributions.modules[0] === a2)
    }

    @Test func removeDropsOnlyThatID() {
        contributions.add(FakeContributed("a"))
        contributions.add(FakeContributed("b"))
        contributions.remove(id: "a")
        #expect(contributions.modules.map(\.id) == ["b"])
        contributions.remove(id: "missing")
        #expect(contributions.modules.count == 1)
    }

    @Test func showAndCloseDoNothingWithoutHost() {
        #expect(!contributions.isHostAvailable)
        #expect(!contributions.show("a"))
        contributions.close()
    }

    @Test(arguments: [true, false])
    func showReturnsWhatTheHostAnswers(answer: Bool) {
        let host = FakeHost()
        host.result = answer
        contributions.host = host
        #expect(contributions.show("clipboard") == answer)
        #expect(host.toggled == ["clipboard"])
    }

    @Test func closeDelegatesToHost() {
        let host = FakeHost()
        contributions.host = host
        contributions.close()
        #expect(host.closes == 1)
    }

    @Test func isHostAvailableFollowsHost() {
        let host = FakeHost()
        contributions.host = host
        #expect(contributions.isHostAvailable)
        contributions.host = nil
        #expect(!contributions.isHostAvailable)
    }

    @Test func hostIsHeldWeakly() {
        var host: FakeHost? = FakeHost()
        contributions.host = host
        host = nil
        #expect(contributions.host == nil)
        #expect(!contributions.show("a"))
    }

    // MARK: ContributionToggle

    private func decide(
        started: Bool = true, hasModule: Bool = true, expanded: Bool = false, shown: String? = nil,
        visible: Bool = true, blocked: Bool = false
    ) -> ContributionToggle {
        .decide(isStarted: started, hasModule: hasModule, isExpanded: expanded, shownModuleID: shown,
                targetID: "clip", isVisible: visible, isBlocked: blocked)
    }

    @Test func closedIslandOpens() {
        #expect(decide() == .open)
    }

    @Test func openIslandOnAnotherModuleSelects() {
        #expect(decide(expanded: true, shown: "music") == .select)
        #expect(decide(expanded: true, shown: nil) == .select)
    }

    @Test func openIslandOnTheTargetCloses() {
        #expect(decide(expanded: true, shown: "clip") == .close)
    }

    @Test func closingIsAllowedWhenBlockedOrHidden() {
        #expect(decide(expanded: true, shown: "clip", visible: false, blocked: true) == .close)
    }

    @Test func staleShownIDWhileCollapsedIsNotAClose() {
        #expect(decide(expanded: false, shown: "clip") == .open)
    }

    @Test func openAndSelectNeedVisibleAndNotBlocked() {
        #expect(decide(visible: false) == .none)
        #expect(decide(blocked: true) == .none)
        #expect(decide(expanded: true, shown: "music", visible: false) == .none)
        #expect(decide(expanded: true, shown: "music", blocked: true) == .none)
    }

    @Test func notStartedOrUnknownModuleIsNone() {
        #expect(decide(started: false) == .none)
        #expect(decide(hasModule: false) == .none)
        #expect(decide(started: false, expanded: true, shown: "clip") == .none)
        #expect(decide(hasModule: false, expanded: true, shown: "clip") == .none)
    }

    // MARK: IslandModule defaults

    @Test func tabDefaultsComeFromModuleKindOrID() {
        let known = PlainModule(ModuleKind.battery.rawValue)
        #expect(known.tabTitle == ModuleKind.battery.title)
        #expect(known.tabSymbol == ModuleKind.battery.symbol)
        let unknown = PlainModule("custom")
        #expect(unknown.tabTitle == "custom")
        #expect(unknown.tabSymbol == "circle")
    }

    @Test func keyboardAndCaptureDefaultsAreOff() {
        let module = PlainModule("x")
        #expect(!module.takesKeyboard)
        #expect(!module.excludesFromCapture)
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        #expect(!module.handleKeyDown(event))
    }

    // MARK: IslandState

    @Test func expandedSizeIsClampedToThePanel() {
        let state = IslandState()
        state.notchSize = CGSize(width: 188, height: 38)
        let big = FakeContributed("big")
        big.expandedWidth = 2000
        big.expandedContentHeight = 2000
        state.modules = [big]
        #expect(state.expandedSize == IslandController.panelSize)
    }

    @Test func pinnedContributedModuleWithoutContentIsShown() {
        let state = IslandState()
        let a = FakeContributed("a"), b = FakeContributed("b")
        b.hasExpandedContent = false
        state.modules = [a, b]
        #expect(state.expandedModule?.id == "a")
        state.pinnedModuleID = "b"
        #expect(state.expandedModule?.id == "b")
    }

    @Test func selectCallsShownModuleChangeOnlyWhenItChanges() {
        let state = IslandState()
        state.modules = [FakeContributed("a"), FakeContributed("b")]
        var calls = 0
        state.onShownModuleChange = { calls += 1 }
        state.select("b")
        #expect(calls == 1 && state.pinnedModuleID == "b")
        state.select("b")
        state.select("missing")
        #expect(calls == 1)
    }

    @Test func selectNotifiesAfterThePinChanged() {
        let state = IslandState()
        state.modules = [FakeContributed("a"), FakeContributed("b")]
        var seen: String?
        state.onShownModuleChange = { seen = state.pinnedModuleID }
        state.select("a")
        #expect(seen == "a")
    }
}
