//
//  NotchTool.swift
//  thenotch
//

import Foundation

/// The island around the notch, as a tool.
@MainActor
final class NotchTool: Tool {
    let id = ToolKind.notch.id
    private let controller: IslandController

    init(settings: AppSettings) {
        controller = IslandController(settings: settings)
    }

    func start() {
        controller.start()
    }

    func stop() {
        // No-op for now: the notch is always on in Phase 0. Teardown comes in Phase 1.
    }
}
