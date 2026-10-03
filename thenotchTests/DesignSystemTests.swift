//
//  DesignSystemTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

/// Rules from `DESIGN.md` that the tokens must keep.
struct DesignSystemTests {
    @Test func containerCornersAreConcentricWithTheIsland() {
        #expect(IslandStyle.Radius.large + IslandStyle.Spacing.content == IslandStyle.Radius.island)
    }

    @Test func spacingFollowsTheFourPointGrid() {
        typealias S = IslandStyle.Spacing
        let spacing = [S.xs, S.s, S.m, S.l, S.xl]
        #expect(spacing.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
        #expect(spacing == spacing.sorted())
    }

    @Test func controlsMeetTheMacOSDefaultSize() {
        typealias Size = IslandStyle.Size
        let sizes = [Size.control, Size.playerControl]
        #expect(sizes.allSatisfy { $0 >= 28 })
    }

    @Test(arguments: IslandFill.Level.allCases)
    func increaseContrastNeverWeakensAFill(_ level: IslandFill.Level) {
        #expect(level.opacity.increased >= level.opacity.standard)
    }

    /// Non-text elements that carry meaning need 3:1 against what's next
    /// to them (WCAG 1.4.11), in both contrast modes.
    @Test(arguments: [false, true])
    func meaningfulShapesReadAtThreeToOne(increased: Bool) {
        func gray(_ level: IslandFill.Level) -> Double {
            increased ? level.opacity.increased : level.opacity.standard
        }
        // The drop zone's edge on black.
        #expect(Self.contrast(gray(.outline), 0) >= 3)
        // The played part of the progress bar against the unplayed part.
        #expect(Self.contrast(gray(.progress), gray(.track)) >= 3)
    }

    @Test func secondaryTextIsLegibleButTertiaryIsNot() {
        // macOS dark label colors: secondary is 55 % white, tertiary 25 %.
        #expect(Self.contrast(0.55, 0) >= 4.5)
        #expect(Self.contrast(0.25, 0) < 4.5)
    }

    /// WCAG contrast ratio of two sRGB grays (white composited on black at
    /// that opacity).
    static func contrast(_ a: Double, _ b: Double) -> Double {
        func luminance(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (lighter, darker) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
