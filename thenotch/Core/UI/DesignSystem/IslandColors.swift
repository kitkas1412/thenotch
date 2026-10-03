//
//  IslandColors.swift
//  thenotch
//

import SwiftUI

/// Colors of the island, which is always black.
///
/// Text and symbols use the semantic `.primary` and `.secondary` styles
/// (never `.tertiary`: 25 % white on black is 2:1, too faint for text).
/// Shapes use `IslandFill`; status uses `IslandSignal`. Each color means one
/// thing (HIG Color › "Avoid using the same color to mean different things").
enum IslandColors {
    /// The island's background.
    static let surface = Color.black
}

/// A white overlay on the black island, for shapes rather than text.
/// Each level has a stronger variant for Increase Contrast (HIG Color ›
/// "supply … an increased contrast option for each variant").
struct IslandFill: ShapeStyle {
    enum Level: CaseIterable {
        /// Nothing (a control at rest).
        case clear
        /// Under the pointer.
        case hover
        /// A selected or always-filled control.
        case selected
        /// A control being clicked.
        case pressed
        /// The unplayed part of a progress bar.
        case track
        /// The played part of a progress bar.
        case progress
        /// The edge of a drop zone: a non-text element that must read at
        /// 3:1 or more.
        case outline
        /// The edge of a drop zone with files over it.
        case outlineActive

        /// White opacity at standard contrast, and with Increase Contrast.
        var opacity: (standard: Double, increased: Double) {
            switch self {
            case .clear: (0, 0)
            case .hover: (0.12, 0.2)
            case .selected: (0.22, 0.35)
            case .pressed: (0.3, 0.45)
            case .track: (0.2, 0.35)
            case .progress: (0.7, 1)
            case .outline: (0.45, 0.7)
            case .outlineActive: (0.8, 1)
            }
        }
    }

    let level: Level

    func resolve(in environment: EnvironmentValues) -> Color {
        let opacity = level.opacity
        return .white.opacity(environment.colorSchemeContrast == .increased ? opacity.increased : opacity.standard)
    }
}

extension ShapeStyle where Self == IslandFill {
    static func island(_ level: IslandFill.Level) -> IslandFill {
        IslandFill(level: level)
    }
}

/// Status colors. System colors, so they adapt to Increase Contrast; each
/// is paired with a shape or a word, never color alone (HIG Accessibility ›
/// "Convey information with more than color alone").
enum IslandSignal {
    /// A track in Favorites (with a filled star).
    static let favorite = Color.yellow
    /// Charging or plugged in (with a bolt).
    static let charging = Color.green
    /// Low battery (with an empty battery).
    static let critical = Color.red
    /// The selected item (with the selection's shape). The only use of the
    /// accent color in the island (HIG Branding › "Apply your app's
    /// accent color judiciously").
    static let selection = Color.accentColor.opacity(0.55)
}
