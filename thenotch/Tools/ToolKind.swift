//
//  ToolKind.swift
//  thenotch
//

import Foundation

enum ToolKind: String, CaseIterable, Identifiable {
    case notch
    case systemMonitor
    case windowManagement
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: "Notch"
        case .systemMonitor: "System Monitor"
        case .windowManagement: "Window Management"
        case .clipboard: "Clipboard"
        }
    }

    /// SF Symbol for the tool.
    var symbol: String {
        switch self {
        case .notch: "capsule.fill"
        case .systemMonitor: "gauge.with.dots.needle.33percent"
        case .windowManagement: "rectangle.split.2x1"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var summary: String {
        switch self {
        case .notch: "A Dynamic Island around the MacBook notch."
        case .systemMonitor: "CPU, memory, network and disk in the thenotch menu."
        case .windowManagement: "Move and resize windows with keyboard shortcuts."
        case .clipboard: "Clipboard history with search, opened with a shortcut."
        }
    }

    /// Whether the tool is on until the user decides.
    var isOnByDefault: Bool { self == .notch }

    @MainActor
    func makeTool(context: ToolContext) -> Tool {
        switch self {
        case .notch: NotchTool(settings: context.settings, hotKeys: context.hotKeys)
        case .systemMonitor: SystemMonitorTool(sampler: context.systemMonitor)
        case .windowManagement: WindowManagerTool(settings: context.settings, hotKeys: context.hotKeys)
        case .clipboard: ClipboardTool(settings: context.settings, hotKeys: context.hotKeys)
        }
    }
}
