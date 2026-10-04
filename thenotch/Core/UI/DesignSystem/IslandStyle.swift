//
//  IslandStyle.swift
//  thenotch
//

import AppKit
import SwiftUI

/// Layout and motion tokens of the island. Colors live in `IslandColors`,
/// type in `IslandTypography`; `DESIGN.md` explains every value.
///
/// Like the Dynamic Island, the island is always black: views render under
/// a forced dark color scheme and use semantic styles (`.primary`,
/// `.secondary`), which follow Increase Contrast.
enum IslandStyle {
    /// Spacing on a 4 pt grid.
    enum Spacing {
        /// Between lines of one text block (title and subtitle).
        static let xxs: CGFloat = 2
        /// Between tightly related items (tiles, a symbol and its label).
        static let xs: CGFloat = 4
        /// Between items of one group.
        static let s: CGFloat = 8
        /// Between groups; padding around bezeled elements (HIG
        /// Accessibility › Mobility: "about 12 points").
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        /// Padding around elements without a bezel ("about 24 points"),
        /// such as the playback controls.
        static let xl: CGFloat = 24

        /// Equal padding: the margin between expanded content and the
        /// island's visible edge, the same on every side (left, right,
        /// bottom, and below the notch). It is measured to what people see
        /// — a glyph, a text, a filled shape — so controls at an edge
        /// show a fill (or none at all) rather than an invisible hit area.
        /// The island's bottom corners are concentric with it
        /// (`Radius.island`).
        static let content: CGFloat = xl
    }

    /// Corner radii. Rounded rectangles use the continuous style.
    enum Radius {
        /// Bottom corners of the open island: a container's radius plus
        /// the content margin, so the corners are concentric (HIG Live
        /// Activities › "Use consistent margins and concentric placement").
        static let island: CGFloat = large + Spacing.content
        /// Outward flare where the open island meets the menu bar.
        static let islandFlare: CGFloat = 14
        /// Bottom corners of the bare notch (no wings, no flare). With
        /// wings, `IslandState.compactCornerRadius` makes them concentric.
        static let compact: CGFloat = 8
        /// Containers near the island's edge (drop zones, large artwork).
        static let large: CGFloat = 12
        /// Items inside a container (shelf tiles).
        static let medium: CGFloat = 8
        /// Artwork in a compact wing.
        static let small: CGFloat = 5
    }

    /// Fixed sizes of controls and content.
    enum Size {
        /// Minimum hit target: the macOS default control size (HIG
        /// Accessibility › Mobility, 28×28 pt).
        static let control: CGFloat = 28
        /// Small secondary buttons (the shelf stack's ✕ and …): the macOS
        /// minimum control size (HIG Accessibility › Mobility, 20×20 pt).
        static let smallControl: CGFloat = 20
        /// The player's row of controls: previous, play/pause, next, and
        /// the favorite and output buttons on filled circles at its ends.
        static let playerControl: CGFloat = 40
        /// Height of compact wing content, and the width of a square one
        /// such as artwork. The notch's remaining height sets the compact
        /// padding (`IslandState.compactPadding`).
        static let compactContent: CGFloat = 20
        /// Large artwork in the open player.
        static let artwork: CGFloat = 64
        /// File thumbnail on the shelf.
        static let thumbnail: CGFloat = 44
        /// A file in the shelf's stack; the stack is a little larger,
        /// for the fanned-out files behind.
        static let stackThumbnail: CGFloat = 88
        /// Width of a shelf tile's name (two lines).
        static let tileLabelWidth: CGFloat = 68
        /// The island's border while files are dragged in, and once they
        /// are over it.
        static let dropBorder: CGFloat = 1.5
        static let dropBorderActive: CGFloat = 3
        /// Height of the progress bar.
        static let progressBar: CGFloat = 6
        /// Height of the level meter.
        static let levelMeter: CGFloat = 14
        /// Height of one line of `islandLabel`/`islandNumeric` text.
        static let labelLine: CGFloat = 16
        /// Width of a time label beside the progress bar (`88:88`).
        static let timeLabel: CGFloat = 34
    }

    /// SF Symbol point sizes. Symbols scale with the font, not with
    /// `scaleEffect`, so they stay sharp.
    enum SymbolSize: CGFloat {
        /// In a small control (`Size.smallControl`).
        case small = 10
        /// In a compact wing; semibold to match the wing's text.
        case compact = 13
        /// In an icon button.
        case control = 17
        /// Previous/next, and illustrations (drop zones, empty states).
        case large = 22
        /// Play/pause and hero glyphs (battery).
        case hero = 30
    }

    // MARK: - Motion

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Opening the island. With Reduce Motion, a short fade replaces the
    /// spring (HIG Accessibility › "Replacing transitions … with fades").
    static var openAnimation: Animation {
        reduceMotion ? fade : .spring(response: 0.38, dampingFraction: 0.8)
    }

    /// Closing the island: critically damped, no bounce.
    static var closeAnimation: Animation {
        reduceMotion ? fade : .spring(response: 0.45, dampingFraction: 1.0)
    }

    static let fade = Animation.easeOut(duration: 0.15)

    /// Tick of the level meter; it only moves while playing.
    static let levelMeterTick: TimeInterval = 0.3
}

extension View {
    /// The standard margins of a module's expanded content: left, right
    /// and bottom. The island adds the same margin below the notch.
    func islandContentMargins() -> some View {
        padding([.horizontal, .bottom], IslandStyle.Spacing.content)
    }
}

extension Font {
    /// An SF Symbol at one of the island's symbol sizes.
    static func islandSymbol(_ size: IslandStyle.SymbolSize, weight: Font.Weight = .regular) -> Font {
        .system(size: size.rawValue, weight: weight)
    }
}
