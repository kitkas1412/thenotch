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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.island(.track))
                Capsule()
                    .fill(.island(.progress))
                    .frame(width: geometry.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: IslandStyle.Size.progressBar)
        .accessibilityHidden(true)
    }
}
