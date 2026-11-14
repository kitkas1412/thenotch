//
//  WindowLayoutTests.swift
//  thenotchTests
//

import CoreGraphics
import Testing
@testable import thenotch

struct WindowLayoutTests {
    static let areas: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1512, height: 944),
        CGRect(x: 0, y: 0, width: 1511, height: 944),
        CGRect(x: 1512, y: -200, width: 1920, height: 1055),
        CGRect(x: -1025, y: 33, width: 1025, height: 767),
    ]
    let window = CGRect(x: 100, y: 100, width: 600, height: 400)

    func frame(_ action: WindowAction, in area: CGRect) -> CGRect {
        WindowLayout.frame(for: action, windowFrame: window, visibleFrame: area)!
    }

    @Test(arguments: areas)
    func everyFrameIsIntegralAndInsideTheArea(area: CGRect) {
        for action in WindowAction.allCases where !action.changesDisplay {
            let f = frame(action, in: area)
            #expect(area.contains(f), "\(action)")
            #expect(f == f.integral, "\(action)")
            #expect(f.width > 0 && f.height > 0)
        }
    }

    @Test(arguments: areas)
    func displayActionsHaveNoFrame(area: CGRect) {
        for action in [WindowAction.nextDisplay, .previousDisplay] {
            #expect(WindowLayout.frame(for: action, windowFrame: window, visibleFrame: area) == nil)
        }
    }

    @Test(arguments: areas)
    func halvesTileExactly(area: CGRect) {
        let l = frame(.leftHalf, in: area), r = frame(.rightHalf, in: area)
        #expect(l.union(r) == area)
        #expect(l.maxX == r.minX)
        let t = frame(.topHalf, in: area), b = frame(.bottomHalf, in: area)
        #expect(t.union(b) == area)
        #expect(b.maxY == t.minY)
        #expect(t.minY > b.minY)
    }

    @Test(arguments: areas)
    func quartersTileExactly(area: CGRect) {
        let quarters = [WindowAction.topLeft, .topRight, .bottomLeft, .bottomRight].map { frame($0, in: area) }
        #expect(quarters.reduce(CGRect.null) { $0.union($1) } == area)
        for i in quarters.indices {
            for j in quarters.indices where j > i {
                #expect(quarters[i].intersection(quarters[j]).isEmpty)
            }
        }
        #expect(frame(.topLeft, in: area).minY == frame(.topHalf, in: area).minY)
        #expect(frame(.bottomRight, in: area).maxX == area.maxX)
    }

    @Test(arguments: areas)
    func thirdsTileExactly(area: CGRect) {
        let a = frame(.firstThird, in: area), b = frame(.centerThird, in: area), c = frame(.lastThird, in: area)
        #expect(a.union(b).union(c) == area)
        #expect(a.maxX == b.minX && b.maxX == c.minX)
        #expect(a.height == area.height)
    }

    @Test(arguments: areas)
    func twoThirdsShareEdgesWithThirds(area: CGRect) {
        let first = frame(.firstTwoThirds, in: area), last = frame(.lastTwoThirds, in: area)
        #expect(first.minX == area.minX)
        #expect(first.maxX == frame(.centerThird, in: area).maxX)
        #expect(last.maxX == area.maxX)
        #expect(last.minX == frame(.centerThird, in: area).minX)
    }

    @Test(arguments: areas)
    func maximizeIsTheVisibleFrame(area: CGRect) {
        #expect(frame(.maximize, in: area) == area)
    }

    @Test(arguments: areas)
    func centerKeepsSizeAndCenters(area: CGRect) {
        let f = frame(.center, in: area)
        #expect(f.size == window.size)
        #expect(abs(f.midX - area.midX) <= 0.5)
        #expect(abs(f.midY - area.midY) <= 0.5)
    }

    @Test func centerClampsOversizedWindow() {
        let area = CGRect(x: 1512, y: -200, width: 1000, height: 700)
        let big = CGRect(x: 0, y: 0, width: 3000, height: 800)
        let f = WindowLayout.frame(for: .center, windowFrame: big, visibleFrame: area)
        #expect(f == CGRect(x: 1512, y: -200, width: 1000, height: 700))
    }

    // MARK: Displays

    @Test func movedToDisplayKeepsRelativePositionAndSize() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: -100, width: 2000, height: 1600)
        let win = CGRect(x: 100, y: 200, width: 500, height: 400)
        #expect(WindowLayout.movedToDisplay(windowFrame: win, from: source, to: target)
            == CGRect(x: 1200, y: 300, width: 1000, height: 800))
    }

    @Test func movedToDisplayFillsTargetWhenWindowIsLarger() {
        let source = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let target = CGRect(x: 3000, y: 0, width: 1000, height: 700)
        let win = CGRect(x: 0, y: 0, width: 1500, height: 500)
        #expect(WindowLayout.movedToDisplay(windowFrame: win, from: source, to: target) == target)
    }

    @Test func movedToDisplayStaysInsideTarget() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: 0, width: 500, height: 400)
        let win = CGRect(x: 900, y: 700, width: 400, height: 300) // hangs off the source
        let f = WindowLayout.movedToDisplay(windowFrame: win, from: source, to: target)
        #expect(target.contains(f))
    }

    @Test func movedToDisplayWithEmptySourceReturnsTarget() {
        let target = CGRect(x: 10, y: 10, width: 500, height: 400)
        #expect(WindowLayout.movedToDisplay(windowFrame: window, from: .zero, to: target) == target)
    }

    @Test(arguments: [
        (0, 3, true, 1), (2, 3, true, 0), (0, 3, false, 2), (1, 3, false, 0),
        (0, 1, true, 0), (0, 1, false, 0), (0, 2, true, 1), (1, 2, true, 0),
    ])
    func targetScreenIndexWraps(current: Int, count: Int, forward: Bool, expected: Int) {
        #expect(WindowLayout.targetScreenIndex(current: current, count: count, forward: forward) == expected)
    }

    @Test func screenIndexPicksLargestOverlap() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        #expect(WindowLayout.screenIndex(containing: CGRect(x: 900, y: 100, width: 400, height: 200), screens: screens) == 1)
        #expect(WindowLayout.screenIndex(containing: CGRect(x: 700, y: 100, width: 400, height: 200), screens: screens) == 0)
    }

    @Test func screenIndexFallsBackToNearestCenter() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        #expect(WindowLayout.screenIndex(containing: CGRect(x: 5000, y: 0, width: 100, height: 100), screens: screens) == 1)
        #expect(WindowLayout.screenIndex(containing: CGRect(x: -900, y: 0, width: 100, height: 100), screens: screens) == 0)
    }

    @Test func screenIndexIsNilWithoutScreens() {
        #expect(WindowLayout.screenIndex(containing: window, screens: []) == nil)
    }

    // MARK: Coordinates

    @Test func axToCocoaFlipsY() {
        let ax = CGRect(x: 50, y: 100, width: 300, height: 200)
        #expect(WindowLayout.axToCocoa(ax, primaryHeight: 900) == CGRect(x: 50, y: 600, width: 300, height: 200))
    }

    @Test func coordinateConversionRoundTrips() {
        let rect = CGRect(x: -1200, y: -300, width: 640, height: 480)
        let ax = WindowLayout.cocoaToAX(rect, primaryHeight: 982)
        #expect(ax == CGRect(x: -1200, y: 982 + 300 - 480, width: 640, height: 480))
        #expect(WindowLayout.axToCocoa(ax, primaryHeight: 982) == rect)
    }

    // MARK: Actions

    @Test func actionsHaveTitlesAndDisplayFlags() {
        #expect(WindowAction.allCases.count == 17)
        #expect(Set(WindowAction.allCases.map(\.title)).count == 17)
        #expect(WindowAction.allCases.filter(\.changesDisplay) == [.nextDisplay, .previousDisplay])
    }

    @Test func windowShortcutActionsFollowWindowActionOrder() {
        let actions = ShortcutAction.actions(for: .windowManagement)
        #expect(actions.map(\.id) == WindowAction.allCases.map { "windows.\($0.rawValue)" })
        #expect(actions.allSatisfy { $0.tool == .windowManagement })
        #expect(ShortcutAction.actions(for: .notch).map(\.id) == [ShortcutAction.notchToggle.id])
        let ids = ShortcutAction.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
