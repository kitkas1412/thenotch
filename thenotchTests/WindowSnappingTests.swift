//
//  WindowSnappingTests.swift
//  thenotchTests
//

import CoreGraphics
import Foundation
import Testing
@testable import thenotch

private func screen(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> SnapScreen {
    let r = CGRect(x: x, y: y, width: w, height: h)
    return SnapScreen(frame: r, visibleFrame: r)
}

private func detect(_ x: CGFloat, _ y: CGFloat, _ screens: [SnapScreen]) -> (area: SnapArea, screenIndex: Int)? {
    SnapArea.detect(cursor: CGPoint(x: x, y: y), screens: screens)
}

struct SnapDetectSingleScreenTests {
    let screens = [screen(0, 0, 1000, 800)]

    @Test(arguments: [
        (2.0, 400.0, SnapArea.left),
        (4.0, 400.0, .left),
        (996.0, 400.0, .right),
        (500.0, 798.0, .top),
        (500.0, 796.0, .top),
        (2.0, 2.0, .bottomLeft),
        (998.0, 2.0, .bottomRight),
        (2.0, 798.0, .topLeft),
        (998.0, 798.0, .topRight),
    ])
    func detectsAreaAtPoint(x: Double, y: Double, expected: SnapArea) {
        let hit = detect(x, y, screens)
        #expect(hit?.area == expected)
        #expect(hit?.screenIndex == 0)
    }

    @Test(arguments: [
        (500.0, 400.0),   // center
        (5.0, 400.0),     // just outside the edge margin
        (995.0, 400.0),
        (500.0, 795.0),
        (500.0, 2.0),     // bottom edge alone
        (500.0, 0.0),
        (25.0, 0.0),      // bottom edge just outside the corner
    ])
    func noSnapAtPoint(x: Double, y: Double) {
        #expect(detect(x, y, screens) == nil)
    }

    @Test func cornerSizeBoundaryOnTopLeft() {
        #expect(detect(0, 776, screens)?.area == .topLeft)   // 24 from top
        #expect(detect(0, 775, screens)?.area == .left)      // 25 from top
        #expect(detect(24, 799, screens)?.area == .topLeft)
        #expect(detect(25, 799, screens)?.area == .top)
    }

    @Test func cornerSizeBoundaryOnBottomLeft() {
        #expect(detect(0, 24, screens)?.area == .bottomLeft)
        #expect(detect(0, 25, screens)?.area == .left)
        #expect(detect(24, 0, screens)?.area == .bottomLeft)
    }

    @Test func cursorOnFarEdgeStillSnaps() {
        #expect(detect(1000, 400, screens)?.area == .right)
        #expect(detect(1000.5, 400, screens)?.area == .right)
    }

    @Test func cursorOutsideAllScreensIsNil() {
        #expect(detect(1002, 400, screens) == nil)
        #expect(detect(-5, 400, screens) == nil)
        #expect(SnapArea.detect(cursor: .zero, screens: []) == nil)
    }
}

struct SnapDetectMultiScreenTests {
    @Test func sharedVerticalEdgeDoesNotSnapButOuterEdgesDo() {
        let screens = [screen(0, 0, 1000, 800), screen(1000, 0, 1000, 800)]
        #expect(detect(999, 400, screens) == nil)
        #expect(detect(1001, 400, screens) == nil)
        #expect(detect(2, 400, screens)?.area == .left)
        #expect(detect(2, 400, screens)?.screenIndex == 0)
        #expect(detect(1998, 400, screens)?.area == .right)
        #expect(detect(1998, 400, screens)?.screenIndex == 1)
    }

    @Test func topEdgeOfSideBySideScreensStillSnapsAndCornerAtSeamIsNotACorner() {
        let screens = [screen(0, 0, 1000, 800), screen(1000, 0, 1000, 800)]
        let hit = detect(999, 799, screens)
        #expect(hit?.area == .top)
        #expect(hit?.screenIndex == 0)
        #expect(detect(1001, 799, screens)?.area == .top)
        #expect(detect(1001, 799, screens)?.screenIndex == 1)
    }

    @Test func sharedEdgeOnlySuppressedOverOverlappingSpan() {
        let screens = [screen(0, 0, 1000, 800), screen(1000, 0, 1000, 400)]
        #expect(detect(999, 200, screens) == nil)            // beside the other screen
        #expect(detect(999, 600, screens)?.area == .right)   // above its top: free edge
    }

    @Test func stackedScreensShareTopAndBottomEdge() {
        let screens = [screen(0, 0, 1000, 800), screen(0, 800, 1000, 800)]
        #expect(detect(500, 799, screens) == nil)            // top of lower, shared
        #expect(detect(500, 1599, screens)?.area == .top)
        #expect(detect(500, 1599, screens)?.screenIndex == 1)
        #expect(detect(2, 2, screens)?.area == .bottomLeft)
        #expect(detect(2, 2, screens)?.screenIndex == 0)
        #expect(detect(2, 799, screens)?.area == .left)      // not a corner at the seam
    }

    @Test func screenIndexFollowsTheScreenUnderTheCursor() {
        let screens = [screen(0, 0, 1000, 800), screen(1000, 0, 1000, 800)]
        #expect(detect(1500, 2, screens) == nil)
        #expect(detect(1002, 2, screens) == nil)
        #expect(detect(1998, 2, screens)?.screenIndex == 1)
    }
}

struct SnapAreaActionTests {
    @Test func mapsEveryAreaToItsWindowAction() {
        let expected: [SnapArea: WindowAction] = [
            .left: .leftHalf, .right: .rightHalf, .top: .maximize,
            .topLeft: .topLeft, .topRight: .topRight,
            .bottomLeft: .bottomLeft, .bottomRight: .bottomRight,
        ]
        #expect(SnapArea.allCases.count == expected.count)
        for area in SnapArea.allCases {
            #expect(area.action == expected[area])
        }
    }
}

struct DragMotionTests {
    let start = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func originChangeIsMoved() {
        #expect(DragMotion.classify(start: start, current: start.offsetBy(dx: 50, dy: 0)) == .moved)
        #expect(DragMotion.classify(start: start, current: start.offsetBy(dx: 0, dy: -20)) == .moved)
    }

    @Test func sizeChangeIsResized() {
        let wider = CGRect(x: 100, y: 100, width: 450, height: 300)
        #expect(DragMotion.classify(start: start, current: wider) == .resized)
        let resizedFromLeft = CGRect(x: 60, y: 100, width: 440, height: 300)
        #expect(DragMotion.classify(start: start, current: resizedFromLeft) == .resized)
    }

    @Test func identicalFrameIsUnchanged() {
        #expect(DragMotion.classify(start: start, current: start) == .unchanged)
    }

    @Test func subPointJitterIsUnchanged() {
        let jitter = CGRect(x: 100.8, y: 99.5, width: 400.9, height: 299.2)
        #expect(DragMotion.classify(start: start, current: jitter) == .unchanged)
    }

    @Test func moveWithTinySizeJitterIsStillMoved() {
        let current = CGRect(x: 160, y: 100, width: 400.5, height: 299.5)
        #expect(DragMotion.classify(start: start, current: current) == .moved)
    }
}

struct SnapRestoreTests {
    let snapped = CGRect(x: 0, y: 0, width: 500, height: 800)
    let original = CGSize(width: 300, height: 400)

    @Test func keepsGrabPointProportionalUnderCursor() throws {
        // Grabbed 25% across and 12.5% down from the top.
        let frame = try #require(SnapRestore.frame(
            originalSize: original, snappedFrame: snapped,
            grab: CGPoint(x: 125, y: 700), cursor: CGPoint(x: 600, y: 500)))
        #expect(frame.size == original)
        #expect(frame.minX == 525)   // 600 - 0.25 * 300
        #expect(frame.maxY == 550)   // 500 + 0.125 * 400
    }

    @Test func grabOutsideWindowIsClampedToItsBounds() throws {
        let frame = try #require(SnapRestore.frame(
            originalSize: original, snappedFrame: snapped,
            grab: CGPoint(x: -50, y: 900), cursor: CGPoint(x: 400, y: 400)))
        #expect(frame.minX == 400)   // fx clamped to 0
        #expect(frame.maxY == 400)   // fy clamped to 0
    }

    @Test func emptySizesReturnNil() {
        #expect(SnapRestore.frame(originalSize: .zero, snappedFrame: snapped, grab: .zero, cursor: .zero) == nil)
        #expect(SnapRestore.frame(originalSize: original, snappedFrame: .zero, grab: .zero, cursor: .zero) == nil)
    }

    @Test func matchesWithinTwoPointsAtZeroSlack() {
        let observed = CGRect(x: 1, y: -1, width: 501.5, height: 799)
        #expect(SnapRestore.matches(snappedFrame: snapped, observed: observed, slack: 0))
    }

    @Test func sizeOffByMoreThanTwoDoesNotMatch() {
        #expect(!SnapRestore.matches(snappedFrame: snapped, observed: CGRect(x: 0, y: 0, width: 510, height: 800), slack: 50))
        #expect(!SnapRestore.matches(snappedFrame: snapped, observed: CGRect(x: 0, y: 0, width: 500, height: 790), slack: 50))
    }

    @Test func originMovedByExactlySlackPlusToleranceMatches() {
        #expect(SnapRestore.matches(snappedFrame: snapped, observed: snapped.offsetBy(dx: 12, dy: 0), slack: 10))
        #expect(SnapRestore.matches(snappedFrame: snapped, observed: snapped.offsetBy(dx: 0, dy: -12), slack: 10))
    }

    @Test func originBeyondSlackDoesNotMatch() {
        #expect(!SnapRestore.matches(snappedFrame: snapped, observed: snapped.offsetBy(dx: 13, dy: 0), slack: 10))
        #expect(!SnapRestore.matches(snappedFrame: snapped, observed: snapped.offsetBy(dx: 0, dy: 3), slack: 0))
    }
}

struct NativeTilingTests {
    @Test(arguments: [(nil, nil), (true, nil), (false, false), (true, true)] as [(Bool?, Bool?)])
    func macOS14IsAlwaysOff(edge: Bool?, top: Bool?) {
        var values: [String: Any] = [:]
        if let edge { values[NativeTiling.edgeDragKey] = NSNumber(value: edge) }
        if let top { values[NativeTiling.topEdgeDragKey] = NSNumber(value: top) }
        #expect(!NativeTiling.isEdgeDragEnabled(values: values, osMajor: 14))
    }

    @Test func missingKeyOnMacOS15DefaultsToOn() {
        #expect(NativeTiling.isEdgeDragEnabled(values: [:], osMajor: 15))
        #expect(NativeTiling.isEdgeDragEnabled(values: [:], osMajor: 26))
    }

    @Test func explicitValuesOnMacOS15() {
        let key = NativeTiling.edgeDragKey
        let top = NativeTiling.topEdgeDragKey
        #expect(!NativeTiling.isEdgeDragEnabled(values: [key: false, top: false], osMajor: 15))
        #expect(!NativeTiling.isEdgeDragEnabled(values: [key: NSNumber(value: 0), top: NSNumber(value: 0)], osMajor: 15))
        #expect(NativeTiling.isEdgeDragEnabled(values: [key: false], osMajor: 15))        // top missing = on
        #expect(NativeTiling.isEdgeDragEnabled(values: [top: false], osMajor: 15))        // edge missing = on
        #expect(NativeTiling.isEdgeDragEnabled(values: [key: false, top: true], osMajor: 15))
        #expect(NativeTiling.isEdgeDragEnabled(values: [key: true, top: false], osMajor: 15))
        #expect(NativeTiling.isEdgeDragEnabled(values: [key: true], osMajor: 15))
        #expect(NativeTiling.isEdgeDragEnabled(values: [key: NSNumber(value: 1)], osMajor: 15))
    }
}

@MainActor
struct WindowSnapSettingTests {
    let defaults: UserDefaults

    init() {
        let suite = "thenotchTests.WindowSnap.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaultsToOn() {
        #expect(AppSettings(defaults: defaults).windowSnapByDragging)
    }

    @Test func persistsAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.windowSnapByDragging = false
        #expect(defaults.object(forKey: "windows.snapByDragging") as? Bool == false)
        #expect(!AppSettings(defaults: defaults).windowSnapByDragging)
        settings.windowSnapByDragging = true
        #expect(AppSettings(defaults: defaults).windowSnapByDragging)
    }
}
