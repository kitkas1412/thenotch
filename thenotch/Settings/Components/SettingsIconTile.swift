//
//  SettingsIconTile.swift
//  thenotch
//

import SwiftUI

/// A symbol, white on a colored rounded square, like the rows of System
/// Settings. Used for tools and modules.
struct SettingsIconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: SettingsLayout.iconTile, height: SettingsLayout.iconTile)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A primary switch: icon tile, title and what it does.
struct SettingsToggleRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let summary: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                SettingsIconTile(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // A primary setting: a regular switch over the small controls
        // below it (HIG Toggles › Switches).
        .controlSize(.regular)
    }
}

extension ModuleKind {
    /// The icon tile's color.
    var tint: Color {
        switch self {
        case .nowPlaying: .pink
        case .battery: .green
        case .shelf: .blue
        case .hud: .gray
        case .bluetooth: .indigo
        case .notifications: .red
        case .claudeCode: .orange
        }
    }
}

extension ToolKind {
    /// The icon tile's color.
    var tint: Color {
        switch self {
        case .notch: .teal
        case .systemMonitor: .green
        case .windowManagement: .indigo
        }
    }
}
