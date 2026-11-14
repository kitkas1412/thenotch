//
//  SystemMonitorTool.swift
//  thenotch
//

import Foundation

/// CPU, memory, network and disk in the thenotch menu panel. The tool only
/// switches the shared sampler on and off; the panel shows its snapshot.
@MainActor
final class SystemMonitorTool: Tool {
    let id = ToolKind.systemMonitor.id
    private let sampler: SystemSampler

    init(sampler: SystemSampler) {
        self.sampler = sampler
    }

    func start() {
        sampler.isEnabled = true
    }

    func stop() {
        sampler.isEnabled = false
    }
}
