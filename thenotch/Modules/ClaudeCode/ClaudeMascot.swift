//
//  ClaudeMascot.swift
//  thenotch
//

import SwiftUI

/// Claude Code's pixel mascot, as its terminal banner draws it with block
/// characters (`▐▛███▜▌` / `▝▜█████▛▘` / `▘▘ ▝▝`): a body with two eyes,
/// arms at the sides and four legs. Drawn from its pixel grid, so it stays
/// sharp at any size; while `isWorking`, it hops like the terminal's
/// spinner (not under Reduce Motion, or when nobody can see it).
///
/// Each block character is a terminal cell split in four, and a cell is
/// about twice as tall as it is wide: a pixel is too (`pixelAspect`), or
/// the mascot comes out squashed.
struct ClaudeMascot: View {
    /// Width of a pixel in points: 2 makes it 36×20 pt.
    var pixel: CGFloat = 2
    var isWorking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.allowsAmbientAnimation) private var allowsAmbientAnimation

    /// Claude's orange, as Claude Code draws the mascot.
    static let color = Color(red: 215 / 255, green: 119 / 255, blue: 87 / 255)

    /// The pixels, row by row: `#` filled.
    static let rows = [
        "...############...",
        "...##.######.##...",
        ".################.",
        "...############...",
        "....#.#....#.#....",
    ]

    static var size: (columns: Int, rows: Int) {
        (rows.map(\.count).max() ?? 0, rows.count)
    }

    /// A pixel's height over its width: half a terminal cell each way.
    static let pixelAspect: CGFloat = 2

    /// The mascot's size for a pixel width.
    static func frame(pixel: CGFloat) -> CGSize {
        CGSize(width: CGFloat(size.columns) * pixel, height: CGFloat(size.rows) * pixel * pixelAspect)
    }

    var body: some View {
        let frame = Self.frame(pixel: pixel)
        Group {
            if isWorking && !reduceMotion && allowsAmbientAnimation {
                // A hop every 0.6 s, only while Claude works.
                TimelineView(.periodic(from: .now, by: 0.3)) { context in
                    let up = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 2 == 0
                    shape.offset(y: up ? -pixel : 0)
                }
            } else {
                shape
            }
        }
        .frame(width: frame.width, height: frame.height)
        .accessibilityHidden(true)
    }

    private var shape: some View {
        Canvas { context, _ in
            let height = pixel * Self.pixelAspect
            var path = Path()
            for (y, row) in Self.rows.enumerated() {
                for (x, character) in row.enumerated() where character == "#" {
                    path.addRect(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * height, width: pixel, height: height))
                }
            }
            context.fill(path, with: .color(Self.color))
        }
    }
}
