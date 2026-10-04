//
//  IslandEnvironment.swift
//  thenotch
//

import SwiftUI

extension EnvironmentValues {
    /// Files are being dragged toward the island, which is open as a drop
    /// target. Modules can show drop zones meanwhile.
    @Entry var isDraggingFiles = false

    /// The `IslandDropZone` the dragged files are over, by title.
    @Entry var targetedDropZone: String?

    /// Dragged files are over the island but no drop zone: dropped now,
    /// they go to the shown module (the shelf).
    @Entry var isIslandDropTargeted = false

    /// Ambient animation (the level meter) may run: someone can see the
    /// island and Low Power Mode is off (`AmbientConditions`). Views show a
    /// still state otherwise.
    @Entry var allowsAmbientAnimation = true

    /// Call when a view starts dragging something out of the island (e.g.
    /// from `onDrag`), so the island stays open until the drag ends.
    @Entry var beginDragOut: @MainActor () -> Void = {}
}
