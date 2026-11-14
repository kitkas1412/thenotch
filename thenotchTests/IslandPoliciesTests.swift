//
//  IslandPoliciesTests.swift
//  thenotchTests
//

import SwiftUI
import Testing
@testable import thenotch

@MainActor
private class StubModule: IslandModule {
    let id: String
    var hasExpandedContent = true
    init(_ id: String) { self.id = id }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
private final class StubContributed: StubModule, ContributedIslandModule {
    func attach(activities: ActivityCenter) {}
    func detach() {}
}

struct ShownModulePolicyTests {
    private func decide(
        expanded: Bool, keyboard: Bool = false, excludes: Bool = false,
        excluding: Bool = false, task: Bool = false
    ) -> (key: ShownModulePolicy.KeyAction, sharing: ShownModulePolicy.SharingAction) {
        ShownModulePolicy.decide(
            isExpanded: expanded, shownTakesKeyboard: keyboard, shownExcludesCapture: excludes,
            currentlyExcluding: excluding, hasRestoreTask: task)
    }

    @Test func openOnExcludingModuleExcludesAndTakesKey() {
        let d = decide(expanded: true, keyboard: true, excludes: true)
        #expect(d.key == .take)
        #expect(d.sharing == .exclude)
    }

    @Test func tabSwitchWhileOpenKeepsExclusionAndSchedulesNothing() {
        // Clipboard was shown (exclusion on, no restore task), another tab now.
        let d = decide(expanded: true, excluding: true)
        #expect(d.key == .release)
        #expect(d.sharing == .keep)
    }

    @Test func closeSchedulesRestoreOnce() {
        #expect(decide(expanded: false, excluding: true).sharing == .scheduleRestore)
        #expect(decide(expanded: false, excluding: true, task: true).sharing == .keep)
    }

    @Test func closedAndCapturableChangesNothing() {
        let d = decide(expanded: false)
        #expect(d.key == .release)
        #expect(d.sharing == .keep)
    }

    @Test func reopenOnExcludingModuleCancelsPendingRestore() {
        #expect(decide(expanded: true, excludes: true, excluding: true, task: true).sharing == .exclude)
    }

    @Test func reopenOnOtherModuleRestoresAtOnce() {
        #expect(decide(expanded: true, excluding: true, task: true).sharing == .restoreNow)
    }

    @Test func keyIsTakenOnlyWhileOpen() {
        #expect(decide(expanded: false, keyboard: true).key == .release)
        #expect(decide(expanded: true, keyboard: true).key == .take)
    }
}

struct PresentationPolicyTests {
    @Test func closedIslandOpens() {
        #expect(PresentationPolicy.decide(isExpanded: false, hasPresentation: false, shownTakesKeyboard: false) == .open)
    }

    @Test func closedIslandWithPresentationOpens() {
        #expect(PresentationPolicy.decide(isExpanded: false, hasPresentation: true, shownTakesKeyboard: false) == .open)
    }

    @Test func openIslandOwnedByUserIgnores() {
        #expect(PresentationPolicy.decide(isExpanded: true, hasPresentation: false, shownTakesKeyboard: false) == .ignore)
    }

    @Test func runningPresentationSelects() {
        #expect(PresentationPolicy.decide(isExpanded: true, hasPresentation: true, shownTakesKeyboard: false) == .select)
    }

    @Test func neverSwitchesAwayFromKeyboardModule() {
        #expect(PresentationPolicy.decide(isExpanded: true, hasPresentation: true, shownTakesKeyboard: true) == .ignore)
    }
}

@MainActor
struct ExpandedModulePreferenceTests {
    private func state(_ modules: [any IslandModule], activityOf id: String) -> IslandState {
        let state = IslandState()
        state.modules = modules
        state.activities.publish(LiveActivity(id: "a", moduleID: id, priority: 50, expiresAt: nil))
        return state
    }

    @Test func builtInActivityModuleIsPreferred() {
        let music = StubModule("music"), shelf = StubModule("shelf")
        #expect(state([shelf, music], activityOf: "music").expandedModule?.id == "music")
    }

    @Test func contributedActivityDoesNotWinAPlainClick() {
        let shelf = StubModule("shelf"), clip = StubContributed("clip")
        #expect(state([shelf, clip], activityOf: "clip").expandedModule?.id == "shelf")
    }

    @Test func contributedModuleOpensByDefaultWhenAlone() {
        let clip = StubContributed("clip")
        #expect(state([clip], activityOf: "clip").expandedModule?.id == "clip")
    }

    @Test func pinningStillShowsContributedModule() {
        let shelf = StubModule("shelf"), clip = StubContributed("clip")
        let s = state([shelf, clip], activityOf: "clip")
        s.pinnedModuleID = "clip"
        #expect(s.expandedModule?.id == "clip")
    }
}
