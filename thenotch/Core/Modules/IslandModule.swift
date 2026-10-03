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

    /// The island just opened showing this module (e.g. to refresh data
    /// that isn't pushed by notifications).
    func islandDidExpand()

    /// Whether the expanded island has something to show for this module.
    /// Hovering the notch opens the island only if some module does (Now
    /// Playing: a playing or paused track; Shelf: files on it).
    var hasExpandedContent: Bool { get }

    /// Height of this module's expanded content, below the notch and the
    /// margin under it, including its bottom margin. With the notch it
    /// must fit in `IslandController.panelSize`.
    var expandedContentHeight: CGFloat { get }

    /// Width of the widest compact wing's content (leading or trailing),
    /// at most `IslandStyle.Size.compactContent` tall. Content narrower
    /// than this sits snug against the notch.
    var compactContentWidth: CGFloat { get }
}

extension IslandModule {
    func islandDidExpand() {}

    var expandedContentHeight: CGFloat { IslandState.defaultContentHeight }

    var compactContentWidth: CGFloat { IslandStyle.Size.compactContent }
}

/// A module that takes files dropped on the island (the Shelf). While files
/// are dragged toward the notch, the island opens on this module.
@MainActor
protocol FileDropReceiving: IslandModule {
    func receive(_ files: [DroppedFile])
}
