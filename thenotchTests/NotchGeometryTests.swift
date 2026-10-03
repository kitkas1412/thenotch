//
//  NotchGeometryTests.swift
//  thenotchTests
//

import CoreGraphics
import Testing
@testable import thenotch

struct NotchGeometryTests {
    // 14" MacBook Pro at default scaling: 1512×982 pt, 32 pt notch.
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 950)

    @Test func notchedScreenUsesAuxiliaryAreas() {
        let rect = NotchGeometry.notchRect(
            frame: frame,
            visibleFrame: visibleFrame,
            topInset: 32,
            leftArea: CGRect(x: 0, y: 950, width: 662, height: 32),
            rightArea: CGRect(x: 850, y: 950, width: 662, height: 32)
        )
        #expect(rect == CGRect(x: 662, y: 950, width: 188, height: 32))
    }

    @Test func screenWithoutNotchFallsBackToSimulatedNotch() {
        let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rect = NotchGeometry.notchRect(
            frame: external,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050),
            topInset: 0,
            leftArea: nil,
            rightArea: nil
        )
        #expect(rect == CGRect(x: 865, y: 1050, width: 190, height: 30))
    }

    @Test func autoHiddenMenuBarUsesMinimumHeight() {
        let rect = NotchGeometry.notchRect(
            frame: frame,
            visibleFrame: frame,
            topInset: 0,
            leftArea: nil,
            rightArea: nil
        )
        #expect(rect.height == NotchGeometry.minimumFallbackHeight)
        #expect(rect.maxY == frame.maxY)
    }

    @Test func secondaryScreenKeepsItsOrigin() {
        let offset = frame.offsetBy(dx: -1512, dy: 200)
        let rect = NotchGeometry.notchRect(
            frame: offset,
            visibleFrame: visibleFrame.offsetBy(dx: -1512, dy: 200),
            topInset: 32,
            leftArea: CGRect(x: 0, y: 0, width: 662, height: 32),
            rightArea: CGRect(x: 0, y: 0, width: 662, height: 32)
        )
        #expect(rect == CGRect(x: -850, y: 1150, width: 188, height: 32))
    }
}
