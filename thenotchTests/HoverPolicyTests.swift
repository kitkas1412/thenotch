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
}
