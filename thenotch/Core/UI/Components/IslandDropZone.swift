//
//  IslandDropZone.swift
//  thenotch
//

import SwiftUI

/// A dashed target for files dragged onto the island. Its edge reads at
/// 3:1 or more against black (`IslandFill.outline`), and it fills and
/// brightens while files are over it.
struct IslandDropZone: View {
    let symbol: String
    let title: String
    var onDrop: ([DroppedFile]) -> Void

    @State private var isTargeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandStyle.Radius.large, style: .continuous)
        VStack(spacing: IslandStyle.Spacing.xs) {
            Image(systemName: symbol)
                .font(.islandSymbol(.large))
                .accessibilityHidden(true)
            Text(title)
                .font(.islandLabel)
        }
        .foregroundStyle(isTargeted ? .primary : .secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(.island(isTargeted ? .hover : .clear)))
        .overlay(
            shape.strokeBorder(
                .island(isTargeted ? .outlineActive : .outline),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
        )
        .accessibilityElement(children: .combine)
        .onDrop(of: FileDrop.acceptedTypes, isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                let files = await FileDrop.loadFiles(from: providers)
                if !files.isEmpty {
                    onDrop(files)
                }
            }
            return true
        }
    }
}
