//
//  QuitOnCloseTests.swift
//  thenotchTests
//

import ApplicationServices
import Foundation
import Testing
@testable import thenotch

struct WindowInventoryTests {
    typealias W = WindowInventory.CGWindow

    private func window(pid: pid_t = 10, layer: Int = 0, alpha: Double = 1, width: Double = 800, height: Double = 600) -> W {
        W(pid: pid, layer: layer, alpha: alpha, width: width, height: height)
    }

    @Test(arguments: [
        (nil as String?, true),
        ("AXStandardWindow", true),
        ("AXDialog", true),
        ("AXSomethingNew", true),
        ("AXFloatingWindow", false),
        ("AXSystemFloatingWindow", false),
    ])
    func isRealWindowOnlyRejectsFloatingPanels(subrole: String?, expected: Bool) {
        #expect(WindowInventory.isRealWindow(subrole: subrole) == expected)
    }

    @Test func visibleWindowOfTheAppIsFound() {
        #expect(WindowInventory.hasVisibleWindow([window()], pid: 10))
    }

    @Test func emptyListHasNoVisibleWindow() {
        #expect(!WindowInventory.hasVisibleWindow([], pid: 10))
    }

    @Test func otherAppsWindowIsIgnored() {
        #expect(!WindowInventory.hasVisibleWindow([window(pid: 11)], pid: 10))
    }

    @Test func nonZeroLayerIsIgnored() {
        #expect(!WindowInventory.hasVisibleWindow([window(layer: 25), window(layer: -1)], pid: 10))
    }

    @Test func transparentWindowIsIgnored() {
        #expect(!WindowInventory.hasVisibleWindow([window(alpha: 0)], pid: 10))
    }

    @Test func smallWindowBoundaryIs40Points() {
        #expect(!WindowInventory.hasVisibleWindow([window(width: 39, height: 600)], pid: 10))
        #expect(!WindowInventory.hasVisibleWindow([window(width: 800, height: 39)], pid: 10))
        #expect(WindowInventory.hasVisibleWindow([window(width: 40, height: 40)], pid: 10))
    }

    @Test func mixedListFindsTheOneQualifyingWindow() {
        let list = [window(pid: 11), window(layer: 3), window(alpha: 0), window(width: 10), window(pid: 10)]
        #expect(WindowInventory.hasVisibleWindow(list, pid: 10))
        #expect(!WindowInventory.hasVisibleWindow(list.dropLast(), pid: 10))
    }

    @Test func windowsFromParsesRealShapedDictionaries() {
        let info: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: 123),
                kCGWindowLayer as String: 0,
                kCGWindowAlpha as String: 0.5,
                kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 640, "Height": 480] as [String: Any],
            ],
            [
                kCGWindowOwnerPID as String: Int32(7),
                kCGWindowLayer as String: NSNumber(value: 25),
                kCGWindowAlpha as String: 1,
                kCGWindowBounds as String: ["Width": 30.5, "Height": 20] as [String: Any],
            ],
        ]
        #expect(WindowInventory.windows(from: info) == [
            W(pid: 123, layer: 0, alpha: 0.5, width: 640, height: 480),
            W(pid: 7, layer: 25, alpha: 1, width: 30.5, height: 20),
        ])
    }

    @Test func windowsFromAppliesDefaultsForMissingFields() {
        let parsed = WindowInventory.windows(from: [[kCGWindowOwnerPID as String: 5]])
        #expect(parsed == [W(pid: 5, layer: 0, alpha: 1, width: .infinity, height: .infinity)])
        // A window with missing fields counts as visible, to be safe.
        #expect(WindowInventory.hasVisibleWindow(parsed, pid: 5))
    }

    @Test func windowsFromDropsEntriesWithoutOwner() {
        let info: [[String: Any]] = [
            [kCGWindowLayer as String: 0],
            [kCGWindowOwnerPID as String: "oops"],
            [kCGWindowOwnerPID as String: 9],
        ]
        #expect(WindowInventory.windows(from: info).map(\.pid) == [9])
    }
}

struct QuitDecisionTests {
    typealias Input = QuitDecision.Input

    /// Everything says "quit".
    private func input(_ edit: (inout Input) -> Void = { _ in }) -> Input {
        var value = Input(axSubroles: [], cgWindows: [], pid: 10, bundleID: "com.example.app")
        edit(&value)
        return value
    }

    @Test func quitsWhenEveryConditionHolds() {
        #expect(QuitDecision.decide(input()) == .quit)
    }

    @Test func floatingWindowsDoNotKeepTheAppOpen() {
        let value = input { $0.axSubroles = ["AXFloatingWindow", "AXSystemFloatingWindow"] }
        #expect(QuitDecision.decide(value) == .quit)
    }

    @Test(arguments: [
        ["AXStandardWindow"], ["AXDialog"], [nil], ["AXFloatingWindow", "AXStandardWindow"],
    ] as [[String?]])
    func realWindowKeepsTheAppOpen(subroles: [String?]) {
        #expect(QuitDecision.decide(input { $0.axSubroles = subroles }) == .skip(.hasWindow))
    }

    @Test func skipsWhenEachSingleConditionFails() {
        let cases: [(QuitDecision.SkipReason, (inout Input) -> Void)] = [
            (.windowsUnreadable, { $0.axSubroles = nil }),
            (.hasWindow, { $0.axSubroles = ["AXStandardWindow"] }),
            (.windowListUnavailable, { $0.cgWindows = nil }),
            (.hasVisibleWindow, { $0.cgWindows = [.init(pid: 10, layer: 0, alpha: 1, width: 500, height: 500)] }),
            (.notRunning, { $0.isRunning = false }),
            (.notFinishedLaunching, { $0.finishedLaunching = false }),
            (.hidden, { $0.isHidden = true }),
            (.notRegular, { $0.isRegular = false }),
            (.notFrontmost, { $0.isFrontmost = false }),
            (.noBundleID, { $0.bundleID = nil }),
            (.neverQuits, { $0.bundleID = "com.apple.finder" }),
            (.neverQuits, { $0.ownBundleID = "com.example.app" }),
            (.notAllowed, { $0.listedApps = ["com.example.app"] }),
            (.notAllowed, { $0.mode = .onlyListed }),
        ]
        for (reason, edit) in cases {
            #expect(QuitDecision.decide(input(edit)) == .skip(reason), "expected \(reason)")
        }
    }

    @Test func otherAppsVisibleWindowDoesNotBlock() {
        let value = input { $0.cgWindows = [.init(pid: 99, layer: 0, alpha: 1, width: 500, height: 500)] }
        #expect(QuitDecision.decide(value) == .quit)
    }

    @Test func firstFailingConditionWinsInOrder() {
        let value = input {
            $0.axSubroles = nil
            $0.cgWindows = nil
            $0.isRunning = false
            $0.bundleID = nil
        }
        #expect(QuitDecision.decide(value) == .skip(.windowsUnreadable))

        let later = input {
            $0.cgWindows = nil
            $0.isHidden = true
            $0.isFrontmost = false
            $0.bundleID = "com.apple.dock"
            $0.mode = .onlyListed
        }
        #expect(QuitDecision.decide(later) == .skip(.windowListUnavailable))

        let late = input {
            $0.isFrontmost = false
            $0.bundleID = "com.apple.dock"
            $0.mode = .onlyListed
        }
        #expect(QuitDecision.decide(late) == .skip(.notFrontmost))

        let last = input {
            $0.bundleID = "com.apple.dock"
            $0.mode = .onlyListed
        }
        #expect(QuitDecision.decide(last) == .skip(.neverQuits))
    }

    @Test func neverQuitListIsFixed() {
        #expect(QuitDecision.neverQuit == [
            "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
            "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.loginwindow",
        ])
    }

    @Test(arguments: [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.loginwindow",
    ])
    func neverQuitAppsAreSkippedEvenWhenListed(bundleID: String) {
        let value = input {
            $0.bundleID = bundleID
            $0.mode = .onlyListed
            $0.listedApps = [bundleID]
        }
        #expect(QuitDecision.decide(value) == .skip(.neverQuits))
    }

    @Test func ownAppIsNeverQuitEvenWhenListed() {
        let own = AppIdentity.bundleID
        let value = input {
            $0.bundleID = own
            $0.mode = .onlyListed
            $0.listedApps = [own]
        }
        #expect(QuitDecision.decide(value) == .skip(.neverQuits))
    }

    @Test func onlyListedModeQuitsListedAppAndSkipsOthers() {
        let listed = input { $0.mode = .onlyListed; $0.listedApps = ["com.example.app"] }
        #expect(QuitDecision.decide(listed) == .quit)
        let other = input { $0.mode = .onlyListed; $0.listedApps = ["com.example.other"] }
        #expect(QuitDecision.decide(other) == .skip(.notAllowed))
    }

    @Test func allExceptListedModeQuitsUnlistedAppAndSkipsListed() {
        let unlisted = input { $0.listedApps = ["com.example.other"] }
        #expect(QuitDecision.decide(unlisted) == .quit)
        let listed = input { $0.listedApps = ["com.example.app"] }
        #expect(QuitDecision.decide(listed) == .skip(.notAllowed))
    }
}

@MainActor
struct QuitOnCloseSettingsTests {
    let defaults: UserDefaults

    init() {
        let suite = "thenotchTests.QuitOnClose.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaultValues() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.quitOnCloseMode == .allExceptListed)
        #expect(settings.quitOnCloseDelay == 2)
        #expect(settings.quitOnCloseApps.isEmpty)
        #expect(AppSettings.quitOnCloseDelays == [1, 2, 5])
    }

    @Test func valuesPersistAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.quitOnCloseMode = .onlyListed
        settings.quitOnCloseDelay = 5
        settings.quitOnCloseApps = ["com.example.a", "com.example.b"]
        #expect(defaults.string(forKey: "quitOnClose.mode") == "onlyListed")
        #expect(defaults.integer(forKey: "quitOnClose.delay") == 5)
        #expect(defaults.stringArray(forKey: "quitOnClose.apps") == ["com.example.a", "com.example.b"])

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.quitOnCloseMode == .onlyListed)
        #expect(reloaded.quitOnCloseDelay == 5)
        #expect(reloaded.quitOnCloseApps == ["com.example.a", "com.example.b"])
    }

    @Test(arguments: [0, -1, 3, 10])
    func invalidDelayFallsBackTo2(delay: Int) {
        defaults.set(delay, forKey: "quitOnClose.delay")
        #expect(AppSettings(defaults: defaults).quitOnCloseDelay == 2)
    }

    @Test func unknownModeFallsBackToAllExceptListed() {
        defaults.set("bogus", forKey: "quitOnClose.mode")
        #expect(AppSettings(defaults: defaults).quitOnCloseMode == .allExceptListed)
    }

    @Test func modeRawValuesAreStable() {
        #expect(QuitOnCloseMode.allExceptListed.rawValue == "allExceptListed")
        #expect(QuitOnCloseMode.onlyListed.rawValue == "onlyListed")
    }

    @Test func toolIsOffByDefaultAndIdMatchesRawValue() {
        #expect(!ToolKind.quitOnClose.isOnByDefault)
        #expect(ToolKind.quitOnClose.rawValue == "quitOnClose")
        #expect(ToolKind.quitOnClose.id == "quitOnClose")
    }
}

struct WindowSpaceTests {
    typealias W = WindowInventory.CGWindow

    private func window(pid: pid_t = 10, width: Double = 500, height: Double = 500, spaces: Int?) -> W {
        W(pid: pid, layer: 0, alpha: 1, width: width, height: height, spaceCount: spaces)
    }

    @Test func orderedOutWindowIsNotVisible() {
        #expect(!WindowInventory.hasVisibleWindow([window(spaces: 0)], pid: 10))
    }

    @Test(arguments: [nil, 1, 2] as [Int?])
    func unknownOrOnSpaceWindowIsVisible(spaces: Int?) {
        #expect(WindowInventory.hasVisibleWindow([window(spaces: spaces)], pid: 10))
    }

    @Test func orderedOutPlusOtherSpaceWindowIsVisible() {
        #expect(WindowInventory.hasVisibleWindow([window(spaces: 0), window(spaces: 1)], pid: 10))
    }

    @Test func cachedOrderedOutWindowDoesNotBlockQuit() {
        let list = [window(spaces: 0), window(width: 1512, height: 33, spaces: 0), window(pid: 11, spaces: 1)]
        #expect(!WindowInventory.hasVisibleWindow(list, pid: 10))
        let input = QuitDecision.Input(axSubroles: [], cgWindows: list, pid: 10, bundleID: "com.example.app")
        #expect(QuitDecision.decide(input) == .quit)
    }

    @Test func windowsFromAsksSpacesOnlyForCandidatesOfThePid() {
        func entry(_ pid: Int, _ number: Int, layer: Int = 0, alpha: Double = 1, side: Double = 500) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: number,
                kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: ["Width": side, "Height": side] as [String: Any],
            ]
        }
        let info = [entry(10, 1), entry(10, 2, layer: 25), entry(10, 3, alpha: 0), entry(10, 4, side: 10), entry(11, 5), entry(10, 6)]
        var asked: [Int] = []
        let parsed = WindowInventory.windows(from: info, pid: 10) { number in
            asked.append(number)
            return number * 10
        }
        #expect(asked == [1, 6])
        #expect(parsed.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(parsed.map(\.spaceCount) == [10, nil, nil, nil, nil, 60])
    }

    @Test func windowsFromAsksAllPidsWhenNoneGiven() {
        let info: [[String: Any]] = [
            [kCGWindowOwnerPID as String: 1, kCGWindowNumber as String: 7],
            [kCGWindowOwnerPID as String: 2, kCGWindowNumber as String: 8],
        ]
        var asked: [Int] = []
        let parsed = WindowInventory.windows(from: info) { asked.append($0); return 0 }
        #expect(asked == [7, 8])
        #expect(parsed.map(\.spaceCount) == [0, 0])
    }
}

struct WindowOrderedInTests {
    typealias W = WindowInventory.CGWindow

    private func window(pid: pid_t = 10, width: Double = 1512, height: Double = 949, spaces: Int?, orderedIn: Bool?) -> W {
        W(pid: pid, layer: 0, alpha: 1, width: width, height: height, spaceCount: spaces, isOrderedIn: orderedIn)
    }

    @Test func orderedOutWindowThatKeepsASpaceIsNotVisible() {
        #expect(!WindowInventory.hasVisibleWindow([window(spaces: 1, orderedIn: false)], pid: 10))
    }

    @Test(arguments: [(1, true), (1, nil), (nil, true), (nil, nil)] as [(Int?, Bool?)])
    func orderedInOrUnknownWindowIsVisible(spaces: Int?, orderedIn: Bool?) {
        #expect(WindowInventory.hasVisibleWindow([window(spaces: spaces, orderedIn: orderedIn)], pid: 10))
    }

    @Test func spotifyShapeDoesNotBlockQuit() {
        let list = [window(spaces: 1, orderedIn: false)]
        let input = QuitDecision.Input(axSubroles: [], cgWindows: list, pid: 10, bundleID: "com.example.app")
        #expect(QuitDecision.decide(input) == .quit)
    }

    @Test func fullScreenWindowOnAnotherSpaceBlocksQuit() {
        let list = [window(spaces: 287, orderedIn: true)]
        let input = QuitDecision.Input(axSubroles: [], cgWindows: list, pid: 10, bundleID: "com.example.app")
        #expect(QuitDecision.decide(input) == .skip(.hasVisibleWindow))
    }

    @Test func windowsFromAsksOrderedInOnlyForCandidatesOfThePidAndStoresIt() {
        func entry(_ pid: Int, _ number: Int, layer: Int = 0, side: Double = 500) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: number,
                kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1,
                kCGWindowBounds as String: ["Width": side, "Height": side] as [String: Any],
            ]
        }
        let info = [entry(10, 1), entry(10, 2, layer: 25), entry(10, 3, side: 10), entry(11, 4), entry(10, 5)]
        var asked: [Int] = []
        let parsed = WindowInventory.windows(from: info, pid: 10, spaces: { _ in 1 }, orderedIn: { number in
            asked.append(number)
            return number == 1
        })
        #expect(asked == [1, 5])
        #expect(parsed.map(\.isOrderedIn) == [true, nil, nil, nil, false])
    }
}
