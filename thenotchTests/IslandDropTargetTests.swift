//
//  IslandDropTargetTests.swift
//  thenotchTests
//

import CoreGraphics
import Testing
@testable import thenotch

struct IslandDropTargetTests {
    private let targets = [
        IslandDropTarget(id: "Keep on Shelf", frame: CGRect(x: 38, y: 56, width: 292, height: 104), perform: { _ in }),
        IslandDropTarget(id: "AirDrop", frame: CGRect(x: 342, y: 56, width: 140, height: 104), perform: { _ in }),
    ]

    @Test func dropGoesToTheZoneUnderThePointer() {
        #expect(IslandDropTarget.target(at: CGPoint(x: 400, y: 100), in: targets)?.id == "AirDrop")
        #expect(IslandDropTarget.target(at: CGPoint(x: 100, y: 100), in: targets)?.id == "Keep on Shelf")
    }

    @Test func dropOutsideEveryZoneHasNoTarget() {
        // Between the zones, and in the band beside the notch.
        #expect(IslandDropTarget.target(at: CGPoint(x: 336, y: 100), in: targets) == nil)
        #expect(IslandDropTarget.target(at: CGPoint(x: 100, y: 20), in: targets) == nil)
    }
}
