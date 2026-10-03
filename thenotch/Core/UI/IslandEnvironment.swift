//
//  IslandEnvironment.swift
//  thenotch
//

import SwiftUI

extension EnvironmentValues {
    /// Files are being dragged toward the island, which is open as a drop
    /// target. Modules can show drop zones meanwhile.
    @Entry var isDraggingFiles = false

    /// Call when a view starts dragging something out of the island (e.g.
    /// from `onDrag`), so the island stays open until the drag ends.
    @Entry var beginDragOut: @MainActor () -> Void = {}
}
