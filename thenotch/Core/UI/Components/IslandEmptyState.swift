//
//  IslandEmptyState.swift
//  thenotch
//

import SwiftUI

/// What an expanded module shows when it has nothing: a short headline and
/// a message that invites the next step (HIG Writing › empty states).
struct IslandEmptyState: View {
    /// Content height of an empty state without a symbol: a headline line,
    /// a message line and the bottom margin.
    static let contentHeight: CGFloat = 16 + IslandStyle.Spacing.xs + IslandStyle.Size.labelLine + IslandStyle.Spacing.content

    let title: String
    let message: String
    var symbol: String?

    var body: some View {
        VStack(spacing: IslandStyle.Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.islandSymbol(.large))
                    .padding(.bottom, IslandStyle.Spacing.xs)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.islandHeadline)
            Text(message)
                .font(.islandLabel)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centered between equal margins.
        .islandContentMargins()
        .accessibilityElement(children: .combine)
    }
}
