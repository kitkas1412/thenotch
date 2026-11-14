//
//  Tool.swift
//  thenotch
//

import Foundation

/// A tool of the suite. The app hosts several; `ToolHost` starts and stops them.
@MainActor
protocol Tool: AnyObject {
    /// Equals `ToolKind.id`.
    var id: String { get }
    func start()
    func stop()
}

/// What a tool needs from the app to be built.
struct ToolContext {
    let settings: AppSettings
}
