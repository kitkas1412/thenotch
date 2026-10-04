//
//  IslandProgressBar.swift
//  thenotch
//

import SwiftUI

/// Determinate progress as a thick capsule with the done part filled.
/// Decorative for VoiceOver: the caller describes the value.
struct IslandProgressBar: View {
    /// 0…1; values outside are clamped.
    let fraction: Double
    /// Under the pointer or being dragged, when the bar seeks: the done
    /// part turns primary.
    var isHighlighted = false

    /// The fraction at `x` along a bar `width` wide, clamped to 0…1.
    static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.island(.track))
                Capsule()
                    .fill(isHighlighted ? AnyShapeStyle(.primary) : AnyShapeStyle(.island(.progress)))
                    .frame(width: geometry.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: IslandStyle.Size.progressBar)
        .accessibilityHidden(true)
    }
}
