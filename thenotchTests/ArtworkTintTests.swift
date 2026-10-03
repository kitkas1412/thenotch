//
//  ArtworkTintTests.swift
//  thenotchTests
//

import AppKit
import Testing
@testable import thenotch

struct ArtworkTintTests {
    @Test func darkColorfulArtworkIsBrightenedKeepingItsHue() throws {
        // Dark purple, like the artwork in a night-themed cover.
        let tint = try #require(ArtworkTint.legible(red: 0.25, green: 0.1, blue: 0.45))
        #expect(tint.brightness >= 0.9)
        #expect((0.7...0.8).contains(tint.hue))
        #expect((0.35...0.6).contains(tint.saturation))
    }

    @Test func grayArtworkHasNoTint() {
        #expect(ArtworkTint.legible(red: 0.5, green: 0.5, blue: 0.52) == nil)
        #expect(ArtworkTint.legible(red: 0.05, green: 0.05, blue: 0.05) == nil)
    }

    @Test func averageIgnoresTransparentPixels() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try #require(rep.bitmapData)
        // Opaque red, then a transparent green pixel.
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 0]
        for (i, value) in pixels.enumerated() { data[i] = value }
        let average = try #require(ArtworkTint.average(of: rep))
        #expect(average.red == 1 && average.green == 0 && average.blue == 0)
    }
}
