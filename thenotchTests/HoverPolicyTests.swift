//
//  HoverPolicyTests.swift
//  thenotchTests
//

import CoreGraphics
import Testing
@testable import thenotch

struct HoverPolicyTests {
    // 14" MacBook Pro notch: top edge of the screen is y = 982, center x = 756.
    let notch = CGRect(x: 662, y: 950, width: 188, height: 32)
    let expandedSize = CGSize(width: 520, height: 160)

    func action(expanded: Bool, _ x: CGFloat, _ y: CGFloat) -> HoverPolicy.Action {
        HoverPolicy.action(isExpanded: expanded, pointer: CGPoint(x: x, y: y), notch: notch, compactSize: notch.size, expandedSize: expandedSize)
    }

    @Test func compactOpensWhenPointerIsOnNotch() {
        #expect(action(expanded: false, 756, 970) == .open)
    }

    @Test func compactOpensWithPointerPinnedAtTopEdge() {
        #expect(action(expanded: false, 756, 982) == .open)
    }

    @Test func compactOpensWithinEntryPadding() {
        #expect(action(expanded: false, 662 - 5, 970) == .open)
        #expect(action(expanded: false, 756, 950 - 5) == .open)
    }

    @Test func compactIgnoresPointerOutsideEntryRegion() {
        #expect(action(expanded: false, 662 - 7, 970) == .none)
        #expect(action(expanded: false, 756, 950 - 7) == .none)
        #expect(action(expanded: false, 100, 500) == .none)
    }

    @Test func expandedStaysOpenInsideIsland() {
        // Below the notch, but inside the 520×160 expanded island.
        #expect(action(expanded: true, 756 - 250, 830) == .none)
    }

    @Test func expandedStaysOpenWithinExitPadding() {
        // Just outside the island's left edge (496) but inside the padding.
        #expect(action(expanded: true, 496 - 10, 900) == .none)
    }

    @Test func expandedClosesOutsideExitRegion() {
        #expect(action(expanded: true, 496 - 13, 900) == .close)
        #expect(action(expanded: true, 756, 822 - 13) == .close)
    }

    @Test func exitRegionContainsEntryRegion() {
        // Hysteresis: anything that opens the island must keep it open.
        let entry = HoverPolicy.entryRect(notch: notch, compactSize: notch.size)
        let exit = HoverPolicy.exitRect(notch: notch, expandedSize: expandedSize)
        #expect(exit.contains(entry))
    }

    @Test func compactWithWingsOpensOverAWing() {
        let withWings = CGSize(width: notch.width + 120, height: notch.height)
        let action = HoverPolicy.action(
            isExpanded: false,
            pointer: CGPoint(x: 662 - 50, y: 970),
            notch: notch,
            compactSize: withWings,
            expandedSize: expandedSize
        )
        #expect(action == .open)
    }

    // MARK: Dragging files

    func dragAction(expanded: Bool, _ x: CGFloat, _ y: CGFloat) -> HoverPolicy.Action {
        HoverPolicy.action(isExpanded: expanded, isDragging: true, pointer: CGPoint(x: x, y: y), notch: notch, compactSize: notch.size, expandedSize: expandedSize)
    }

    @Test func dragOpensFromFurtherAway() {
        // 30pt below the notch: too far for hovering, close enough for a drag.
        #expect(action(expanded: false, 756, 950 - 30) == .none)
        #expect(dragAction(expanded: false, 756, 950 - 30) == .open)
        #expect(dragAction(expanded: false, 662 - 39, 970) == .open)
    }

    @Test func dragIgnoresPointerOutsideDragEntryRegion() {
        #expect(dragAction(expanded: false, 756, 950 - 41) == .none)
        #expect(dragAction(expanded: false, 662 - 41, 970) == .none)
    }

    @Test func dragClosesLikeHoverOnceExpanded() {
        #expect(dragAction(expanded: true, 756, 830) == .none)
        #expect(dragAction(expanded: true, 756, 822 - 13) == .close)
    }

    @Test func exitRegionContainsDragEntryRegion() {
        let withWings = CGSize(width: notch.width + 120, height: notch.height)
        for compact in [notch.size, withWings] {
            let entry = HoverPolicy.dragEntryRect(notch: notch, compactSize: compact)
            let exit = HoverPolicy.exitRect(notch: notch, expandedSize: expandedSize)
            #expect(exit.contains(entry))
        }
    }

    @Test func dragKeepsANarrowIslandOpenAroundWideWings() {
        let wings = CGSize(width: notch.width + 200, height: notch.height)
        let square = CGSize(width: 256, height: 232)
        // Beside the wings, outside the narrow island: still where a drag opens it.
        let pointer = CGPoint(x: 662 - 120, y: 970)
        #expect(HoverPolicy.action(isExpanded: false, isDragging: true, pointer: pointer, notch: notch, compactSize: wings, expandedSize: square) == .open)
        #expect(HoverPolicy.action(isExpanded: true, isDragging: true, pointer: pointer, notch: notch, compactSize: wings, expandedSize: square) == .none)
        #expect(HoverPolicy.action(isExpanded: true, pointer: pointer, notch: notch, compactSize: wings, expandedSize: square) == .close)
    }

    // MARK: Shrinking under the pointer

    @Test func shrinkingKeepsTheOldRegionUntilThePointerIsBack() {
        var grace = HoverPolicy.ShrinkGrace()
        let wide = CGSize(width: 520, height: 160)
        let square = CGSize(width: 256, height: 232)
        #expect(grace.exitSize(for: wide) { _ in true } == wide)
        // Shrunk with the pointer outside the square: the wide region counts too.
        #expect(grace.exitSize(for: square) { _ in false } == CGSize(width: 520, height: 232))
        #expect(grace.exitSize(for: square) { _ in false } == CGSize(width: 520, height: 232))
        // Back over the island: only the square counts.
        #expect(grace.exitSize(for: square) { _ in true } == square)
        #expect(grace.exitSize(for: square) { _ in false } == square)
    }

    @Test func growingNeedsNoGrace() {
        var grace = HoverPolicy.ShrinkGrace()
        let square = CGSize(width: 256, height: 232)
        let wide = CGSize(width: 520, height: 232)
        _ = grace.exitSize(for: square) { _ in true }
        #expect(grace.exitSize(for: wide) { _ in false } == wide)
    }

    @Test func graceEndsWhenTheIslandCloses() {
        var grace = HoverPolicy.ShrinkGrace()
        _ = grace.exitSize(for: CGSize(width: 520, height: 160)) { _ in true }
        grace.reset()
        let square = CGSize(width: 256, height: 232)
        #expect(grace.exitSize(for: square) { _ in false } == square)
    }
}
