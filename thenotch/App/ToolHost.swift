//
//  ToolHost.swift
//  thenotch
//

import Foundation

/// Owns the suite's tools: builds them at init, starts them in `ToolKind`
/// order and stops them in reverse. With `settings`, only the tools enabled
/// there run, and switching one in Settings starts or stops it while the
/// host is started.
@MainActor
final class ToolHost {
    private let tools: [Tool]
    private let settings: AppSettings?
    private(set) var runningIDs: [String] = []
    /// Between `start()` and `stop()`.
    private var isStarted = false

    init(
        kinds: [ToolKind] = ToolKind.allCases,
        settings: AppSettings? = nil,
        make: (ToolKind) -> Tool
    ) {
        tools = kinds.map(make)
        self.settings = settings
        settings?.onToolsChange = { [weak self] in
            self?.apply()
        }
    }

    convenience init(context: ToolContext) {
        self.init(settings: context.settings, make: { $0.makeTool(context: context) })
    }

    func start() {
        isStarted = true
        apply()
    }

    func stop() {
        isStarted = false
        for tool in tools.reversed() where runningIDs.contains(tool.id) {
            tool.stop()
            runningIDs.removeAll { $0 == tool.id }
        }
    }

    /// Without settings a tool is enabled if it is on by default.
    private func isEnabled(_ tool: Tool) -> Bool {
        guard let kind = ToolKind(rawValue: tool.id) else { return settings == nil }
        guard let settings else { return kind.isOnByDefault }
        return settings.isToolEnabled(kind)
    }

    /// Stops disabled tools (in reverse) and starts enabled ones (in order).
    private func apply() {
        guard isStarted else { return }
        for tool in tools.reversed() where runningIDs.contains(tool.id) && !isEnabled(tool) {
            tool.stop()
            runningIDs.removeAll { $0 == tool.id }
        }
        for tool in tools where !runningIDs.contains(tool.id) && isEnabled(tool) {
            tool.start()
            runningIDs.append(tool.id)
        }
        runningIDs = tools.map(\.id).filter(runningIDs.contains)
    }
}
