//
//  ArtworkTint.swift
//  thenotch
//

import AppKit

/// An accent color taken from the album artwork, for the level meter and
/// progress bar, so the island picks up the music's character (HIG Live
/// Activities: "Use color to express the character and identity").
enum ArtworkTint {
    /// Average color of a bitmap, ignoring transparent pixels.
    static func average(of rep: NSBitmapImageRep) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel >= 3 else { return nil }
        var red = 0, green = 0, blue = 0, count = 0
        let samples = rep.samplesPerPixel
        for y in 0..<rep.pixelsHigh {
            let row = data + y * rep.bytesPerRow
            for x in 0..<rep.pixelsWide {
                let pixel = row + x * samples
                if samples == 4 && pixel[3] < 128 { continue }
                red += Int(pixel[0])
                green += Int(pixel[1])
                blue += Int(pixel[2])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let total = CGFloat(count) * 255
        return (CGFloat(red) / total, CGFloat(green) / total, CGFloat(blue) / total)
    }

    /// The artwork's hue, made bright enough to read on the black island.
    /// `nil` for nearly gray artwork: plain white reads better than a
    /// muddy tint.
    static func legible(red: CGFloat, green: CGFloat, blue: CGFloat) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)? {
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        guard saturation >= 0.15 else { return nil }
        return (hue, min(max(saturation, 0.35), 0.6), max(brightness, 0.9))
    }

    static func tint(of rep: NSBitmapImageRep) -> NSColor? {
        guard let average = average(of: rep),
              let hsb = legible(red: average.red, green: average.green, blue: average.blue)
        else { return nil }
        return NSColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness, alpha: 1)
    }
}
