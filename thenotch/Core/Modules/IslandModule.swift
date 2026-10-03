//
//  IslandModule.swift
//  thenotch
//

import SwiftUI

/// A feature shown in the island (Now Playing, Battery, Timer…).
///
/// A module talks to the system through its own services, publishes a
/// `LiveActivity` to `ActivityCenter` while it has something to show, and
/// provides the views the island renders for it. A module that is never
/// started costs nothing.
@MainActor
protocol IslandModule: AnyObject {
    /// Stable identifier, also used as `LiveActivity.moduleID`.
    var id: String { get }

    func start()
    func stop()

    /// Shown left of the notch while this module's activity is current.
    func compactLeading() -> AnyView
    /// Shown right of the notch while this module's activity is current.
    func compactTrailing() -> AnyView
    /// Content of the expanded island, below the notch.
    func expandedView() -> AnyView
}
