//
//  IslandStyle.swift
//  thenotch
//

import AppKit
import SwiftUI

/// Shared look of the island. Like the Dynamic Island it is always black,
/// so views render under a forced dark color scheme and use semantic
/// styles (`.primary`, `.secondary`): those follow Increase Contrast.
enum IslandStyle {
    static let hoverFill = Color.white.opacity(0.12)
    static let pressedFill = Color.white.opacity(0.3)
    /// Selected tab in the module switcher: a visible shape, not only a
    /// brighter icon (#383838 on black).
    static let selectedFill = Color.white.opacity(0.22)
    /// Hit target for the island's controls: the macOS default control size.
    static let controlSize: CGFloat = 28

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Opening and closing the island. With Reduce Motion, a short fade
    /// replaces the bouncy spring.
    static var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8)
    }

    static var closeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 1.0)
    }
}

/// Icon-only button in the island: 28×28 pt hit target, hover and pressed
/// feedback, and a filled circle when selected. Give it a `Label` so
/// VoiceOver reads the title.
struct IslandIconButtonStyle: ButtonStyle {
    var isSelected = false
    /// Always sits on a filled circle (e.g. the player's app button).
    var isFilled = false
    /// Always full strength (primary controls such as play/pause).
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, isSelected: isSelected || isFilled, isProminent: isProminent, shape: Circle(), insets: EdgeInsets())
            .labelStyle(.iconOnly)
            .frame(minWidth: IslandStyle.controlSize, minHeight: IslandStyle.controlSize)
    }
}

/// Text button in the island (shelf actions): hover and pressed feedback.
struct IslandTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, isSelected: false, isProminent: false, shape: Capsule(), insets: EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            .font(.callout.weight(.medium))
    }
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
            .background(shape.fill(fill))
            .contentShape(shape)
            .onHover { isHovering = $0 }
    }

    private var fill: Color {
        if configuration.isPressed { return IslandStyle.pressedFill }
        if isSelected { return IslandStyle.selectedFill }
        return isHovering ? IslandStyle.hoverFill : .clear
    }
}
