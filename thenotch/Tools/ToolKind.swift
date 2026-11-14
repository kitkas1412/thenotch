//
//  ToolKind.swift
//  thenotch
//

import Foundation

enum ToolKind: String, CaseIterable, Identifiable {
    case notch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: "Notch"
        }
    }

    /// SF Symbol for the tool.
    var symbol: String {
        switch self {
        case .notch: "capsule.fill"
        }
    }

    var summary: String {
        switch self {
        case .notch: "A Dynamic Island around the MacBook notch."
        }
    }

    /// Whether the tool is on until the user decides.
    var isOnByDefault: Bool { true }

    @MainActor
    func makeTool(context: ToolContext) -> Tool {
        switch self {
        case .notch: NotchTool(settings: context.settings, hotKeys: context.hotKeys)
        }
    }
}
