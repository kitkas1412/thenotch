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

    func hover(hovering: Bool, _ x: CGFloat, _ y: CGFloat, compactSize: CGSize? = nil) -> HoverPolicy.HoverAction {
        HoverPolicy.hoverAction(isHovering: hovering, pointer: CGPoint(x: x, y: y), notch: notch, compactSize: compactSize ?? notch.size, scale: IslandStyle.hoverScale)
    }

    // MARK: Hovering the compact island

    @Test func compactHoversWhenPointerIsOnNotch() {
        #expect(hover(hovering: false, 756, 970) == .hover)
    }

    @Test func compactHoversWithPointerPinnedAtTopEdge() {
        #expect(hover(hovering: false, 756, 982) == .hover)
    }

    @Test func compactHoversWithinEntryPadding() {
        #expect(hover(hovering: false, 662 - 5, 970) == .hover)
        #expect(hover(hovering: false, 756, 950 - 5) == .hover)
    }

    @Test func compactIgnoresPointerOutsideEntryRegion() {
        #expect(hover(hovering: false, 662 - 7, 970) == .none)
        #expect(hover(hovering: false, 756, 950 - 7) == .none)
        #expect(hover(hovering: false, 100, 500) == .none)
    }

    @Test func hoveringStaysInsideGrownRegion() {
        #expect(hover(hovering: true, 756, 970) == .none)
        // Beyond the notch's own edge, still within the grown island.
        let grown = HoverPolicy.hoverExitRect(notch: notch, compactSize: notch.size, scale: IslandStyle.hoverScale)
        #expect(hover(hovering: true, grown.minX + 1, 970) == .none)
    }

    @Test func hoveringKeepsHoverJustOutsideEntryRegion() {
        // Hysteresis: 8pt left of the notch no longer starts a hover, but keeps one.
        let x = 662 - 8
        #expect(HoverPolicy.entryRect(notch: notch, compactSize: notch.size).contains(CGPoint(x: x, y: 970)) == false)
        #expect(hover(hovering: false, CGFloat(x), 970) == .none)
        #expect(hover(hovering: true, CGFloat(x), 970) == .none)
    }

    @Test func hoveringEndsOutsideHoverExitRegion() {
        let exit = HoverPolicy.hoverExitRect(notch: notch, compactSize: notch.size, scale: IslandStyle.hoverScale)
        #expect(hover(hovering: true, exit.minX - 1, 970) == .unhover)
        #expect(hover(hovering: true, exit.maxX + 1, 970) == .unhover)
        #expect(hover(hovering: true, 756, exit.minY - 1) == .unhover)
        #expect(hover(hovering: true, 100, 500) == .unhover)
    }

    @Test func hoverExitRegionContainsEntryRegion() {
        // Hysteresis: anything that starts a hover must keep it.
        let withWings = CGSize(width: notch.width + 120, height: notch.height)
        for compact in [notch.size, withWings] {
            let entry = HoverPolicy.entryRect(notch: notch, compactSize: compact)
            let exit = HoverPolicy.hoverExitRect(notch: notch, compactSize: compact, scale: IslandStyle.hoverScale)
            #expect(exit.contains(entry))
        }
    }

    @Test func compactWithWingsHoversOverAWing() {
        let withWings = CGSize(width: notch.width + 120, height: notch.height)
        #expect(hover(hovering: false, 662 - 50, 970, compactSize: withWings) == .hover)
        #expect(hover(hovering: false, 662 - 50, 970) == .none)
    }

    @Test func grownSizeScalesByHoverScale() {
        let size = CGSize(width: 200, height: 32)
        let grown = HoverPolicy.grownSize(size, scale: IslandStyle.hoverScale)
        #expect(grown.width == size.width * IslandStyle.hoverScale)
        #expect(grown.height == size.height * IslandStyle.hoverScale)
        #expect(grown.width > size.width)
    }

    // MARK: Clicks

    func click(expanded: Bool, hovering: Bool = false, blocked: Bool = false, _ x: CGFloat, _ y: CGFloat) -> HoverPolicy.ClickAction {
        HoverPolicy.clickAction(isExpanded: expanded, isHovering: hovering, isBlocked: blocked, pointer: CGPoint(x: x, y: y), notch: notch, compactSize: notch.size, expandedSize: expandedSize, scale: IslandStyle.hoverScale)
    }

    @Test func blockedClickDoesNothing() {
        #expect(click(expanded: true, blocked: true, 100, 500) == .none)
        #expect(click(expanded: true, blocked: true, 756, 970) == .none)
        #expect(click(expanded: false, hovering: true, blocked: true, 756, 970) == .none)
    }

    @Test func expandedClickFarOutsideCloses() {
        #expect(click(expanded: true, 100, 500) == .close)
        #expect(click(expanded: true, 756, 822 - 1) == .close)
        #expect(click(expanded: true, 756 + 261, 900) == .close)
    }

    @Test func expandedClickOnNotchCloses() {
        #expect(click(expanded: true, 756, 970) == .close)
        #expect(click(expanded: true, 756, 982) == .close)
    }

    @Test func expandedClickInsideContentBelowNotchIsIgnored() {
        #expect(click(expanded: true, 756, 900) == .none)
        #expect(click(expanded: true, 756, 950 - 1) == .none)
    }

    @Test func expandedClickBesideNotchInsideIslandIsIgnored() {
        // Tab area: left and right of the notch, within the island's width.
        #expect(click(expanded: true, 580, 970) == .none)
        #expect(click(expanded: true, 930, 970) == .none)
    }

    @Test func compactClickWithoutHoverDoesNothing() {
        #expect(click(expanded: false, hovering: false, 756, 970) == .none)
    }

    @Test func compactClickWhileHoveringOnIslandOpens() {
        #expect(click(expanded: false, hovering: true, 756, 970) == .open)
        #expect(click(expanded: false, hovering: true, 756, 982) == .open)
    }

    @Test func compactClickWhileHoveringInGrownRegionOpens() {
        let grown = HoverPolicy.hoverExitRect(notch: notch, compactSize: notch.size, scale: IslandStyle.hoverScale)
        let x = grown.minX + 1
        // Just outside the compact island, still within the grown one.
        #expect(HoverPolicy.isOnIsland(pointer: CGPoint(x: x, y: 970), notch: notch, size: notch.size) == false)
        #expect(click(expanded: false, hovering: true, x, 970) == .open)
    }

    @Test func compactClickWhileHoveringOutsideGrownRegionDoesNothing() {
        let grown = HoverPolicy.hoverExitRect(notch: notch, compactSize: notch.size, scale: IslandStyle.hoverScale)
        #expect(click(expanded: false, hovering: true, grown.minX - 1, 970) == .none)
        #expect(click(expanded: false, hovering: true, 100, 500) == .none)
    }

    @Test func isOnIslandInsideAndJustOutside() {
        let size = expandedSize
        func on(_ x: CGFloat, _ y: CGFloat) -> Bool {
            HoverPolicy.isOnIsland(pointer: CGPoint(x: x, y: y), notch: notch, size: size)
        }
        #expect(on(756, 900))
        #expect(on(756 - 259, 900))
        #expect(on(756 + 259, 900))
        #expect(on(756 - 261, 900) == false)
        #expect(on(756 + 261, 900) == false)
        #expect(on(756, 982 - 160 - 1) == false)
    }

    @Test func isOnIslandIsCenteredOnNotchMidXWithNoPadding() {
        let size = CGSize(width: 100, height: 40)
        func on(_ x: CGFloat) -> Bool {
            HoverPolicy.isOnIsland(pointer: CGPoint(x: x, y: 970), notch: notch, size: size)
        }
        #expect(on(notch.midX - 49))
        #expect(on(notch.midX + 49))
        #expect(on(notch.midX - 51) == false)
        #expect(on(notch.midX + 51) == false)
    }

    @Test func isOnIslandCountsTheTopEdge() {
        #expect(HoverPolicy.isOnIsland(pointer: CGPoint(x: 756, y: 982), notch: notch, size: notch.size))
        #expect(HoverPolicy.isOnIsland(pointer: CGPoint(x: 756, y: 984), notch: notch, size: notch.size) == false)
    }

    // MARK: Dragging files

    func dragAction(expanded: Bool, _ x: CGFloat, _ y: CGFloat) -> HoverPolicy.Action {
        HoverPolicy.dragAction(isExpanded: expanded, pointer: CGPoint(x: x, y: y), notch: notch, compactSize: notch.size, expandedSize: expandedSize)
    }

    @Test func dragOpensFromFurtherAway() {
        // 30pt below the notch: too far for hovering, close enough for a drag.
        #expect(hover(hovering: false, 756, 950 - 30) == .none)
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
        #expect(HoverPolicy.dragAction(isExpanded: false, pointer: pointer, notch: notch, compactSize: wings, expandedSize: square) == .open)
        #expect(HoverPolicy.dragAction(isExpanded: true, pointer: pointer, notch: notch, compactSize: wings, expandedSize: square) == .none)
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
