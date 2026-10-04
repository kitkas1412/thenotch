//
//  IslandDropZone.swift
//  thenotch
//

import SwiftUI

/// A dashed target for files dragged onto the island. Its edge reads at
/// 3:1 or more against black (`IslandFill.outline`), and it fills and
/// brightens while files are over it.
///
/// The zone only reports where it is (`IslandDropTarget`); `IslandView`
/// takes the drop and hands the files to the zone under the pointer. A
/// zone can't take drops itself: `onDrop` adds an AppKit view, and inside
/// the island's clip shape AppKit misplaces it, so drops miss it.
struct IslandDropZone: View {
    let symbol: String
    let title: String
    var onDrop: ([DroppedFile]) -> Void

    @Environment(\.targetedDropZone) private var targetedDropZone

    var body: some View {
        let isTargeted = targetedDropZone == title
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
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IslandDropTarget.Key.self,
                    value: [IslandDropTarget(
                        id: title,
                        frame: proxy.frame(in: .named(IslandDropTarget.coordinateSpace)),
                        perform: onDrop
                    )]
                )
            }
        }
    }
}

/// A drop zone's place on the island, and what it does with the files.
struct IslandDropTarget: Equatable {
    /// The space `frame` is in: the island's, where `IslandView` takes drops.
    static let coordinateSpace = "island.drop"

    let id: String
    let frame: CGRect
    let perform: ([DroppedFile]) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame
    }

    /// The zone under `point`, if any.
    static func target(at point: CGPoint, in targets: [IslandDropTarget]) -> IslandDropTarget? {
        targets.last { $0.frame.contains(point) }
    }

    struct Key: PreferenceKey {
        static let defaultValue: [IslandDropTarget] = []

        static func reduce(value: inout [IslandDropTarget], nextValue: () -> [IslandDropTarget]) {
            value.append(contentsOf: nextValue())
        }
    }
}
