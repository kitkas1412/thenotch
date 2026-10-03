//
//  IslandButtonStyles.swift
//  thenotch
//

import SwiftUI

/// Icon-only button in the island: at least a 28×28 pt hit target, hover
/// and pressed feedback, and a filled circle when selected. Give it a
/// `Label` so VoiceOver reads the title.
struct IslandIconButtonStyle: ButtonStyle {
    var isSelected = false
    /// Always sits on a filled circle (e.g. the favorite star).
    var isFilled = false
    /// Always full strength (primary controls such as play/pause).
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, isSelected: isSelected || isFilled, isProminent: isProminent, shape: Circle(), insets: EdgeInsets())
            .labelStyle(.iconOnly)
            .frame(minWidth: IslandStyle.Size.control, minHeight: IslandStyle.Size.control)
    }
}

/// Text button in the island (shelf actions): a capsule on hover, title-style
/// capitalization like other macOS buttons.
struct IslandTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, isSelected: false, isProminent: false, shape: Capsule(), insets: Self.insets)
            .font(.islandLabel)
    }

    /// 12 pt text plus these insets keeps the capsule ≥ 20 pt tall, the
    /// macOS minimum control size. Callers may pull the capsule into a
    /// margin by these amounts so the text lines up with other content.
    static let verticalInset: CGFloat = 3
    private static let insets = EdgeInsets(top: verticalInset, leading: IslandStyle.Spacing.s, bottom: verticalInset, trailing: IslandStyle.Spacing.s)
}

extension ButtonStyle where Self == IslandIconButtonStyle {
    static func islandIcon(isSelected: Bool = false, isFilled: Bool = false, isProminent: Bool = false) -> IslandIconButtonStyle {
        IslandIconButtonStyle(isSelected: isSelected, isFilled: isFilled, isProminent: isProminent)
    }
}

extension ButtonStyle where Self == IslandTextButtonStyle {
    static var islandText: IslandTextButtonStyle { IslandTextButtonStyle() }
}

private struct IslandButtonBody<S: Shape>: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let isProminent: Bool
    let shape: S
    let insets: EdgeInsets

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(insets)
            .foregroundStyle(isProminent || isSelected || isHovering ? .primary : .secondary)
            .background(shape.fill(.island(fill)))
            .contentShape(shape)
            .onHover { isHovering = $0 }
    }

    private var fill: IslandFill.Level {
        if configuration.isPressed { return .pressed }
        if isSelected { return .selected }
        return isHovering ? .hover : .clear
    }
}
