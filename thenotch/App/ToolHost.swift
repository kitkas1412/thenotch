//
//  ToolHost.swift
//  thenotch
//

import Foundation

/// Owns the suite's tools: builds them at init, starts them in `ToolKind`
/// order and stops them in reverse.
@MainActor
final class ToolHost {
    private let tools: [Tool]
    private(set) var runningIDs: [String] = []

    init(
        kinds: [ToolKind] = ToolKind.allCases.filter(\.isOnByDefault),
        make: (ToolKind) -> Tool
    ) {
        tools = kinds.map(make)
    }

    convenience init(context: ToolContext) {
        self.init(make: { $0.makeTool(context: context) })
    }

    func start() {
        for tool in tools where !runningIDs.contains(tool.id) {
            tool.start()
            runningIDs.append(tool.id)
        }
    }

    func stop() {
        for tool in tools.reversed() where runningIDs.contains(tool.id) {
            tool.stop()
            runningIDs.removeAll { $0 == tool.id }
        }
    }
}
