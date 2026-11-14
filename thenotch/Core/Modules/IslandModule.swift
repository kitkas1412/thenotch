//
//  IslandModule.swift
//  thenotch
//

import AppKit
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
    /// The user turned the module off.
    func stop()
    /// The island is going away (the Notch tool was turned off) while the
    /// module stays on in Settings: stop working, but keep anything the
    /// user set up by turning it on (AI Agents keeps its hooks). A later
    /// `start()` on a new instance resumes. Defaults to `stop()`.
    func suspend()

    /// Shown left of the notch while this module's activity is current.
    func compactLeading() -> AnyView
    /// Shown right of the notch while this module's activity is current.
    func compactTrailing() -> AnyView
    /// Content of the expanded island, below the notch.
    func expandedView() -> AnyView

    /// The island just opened showing this module (e.g. to refresh data
    /// that isn't pushed by notifications).
    func islandDidExpand()

    /// The island closed. A module whose open layout changes while open
    /// (the shelf's stack and list) goes back to the one it opens with.
    func islandDidCollapse()

    /// Whether the expanded island has something to show for this module.
    /// Hovering the notch opens the island only if some module does (Now
    /// Playing: a playing or paused track; Shelf: files on it).
    var hasExpandedContent: Bool { get }

    /// Height of this module's expanded content, below the notch and the
    /// margin under it, including its bottom margin. With the notch it
    /// must fit in `IslandController.panelSize`.
    var expandedContentHeight: CGFloat { get }

    /// Width of the open island while it shows this module. Most modules
    /// use the standard `IslandState.expandedWidth`; the shelf's stack is
    /// narrower. It must stay ≤ `IslandController.panelSize.width`.
    var expandedWidth: CGFloat { get }

    /// Width of the widest compact wing's content (leading or trailing),
    /// at most `IslandStyle.Size.compactContent` tall. Content narrower
    /// than this sits snug against the notch.
    var compactContentWidth: CGFloat { get }

    /// Title of the module's tab (also its tooltip).
    var tabTitle: String { get }
    /// SF Symbol of the module's tab.
    var tabSymbol: String { get }

    /// The module takes typing while it is shown: the island's panel
    /// becomes the key window (without activating the app) and offers key
    /// presses to `handleKeyDown(_:)`. Typing leaves the island when the
    /// module is no longer shown.
    var takesKeyboard: Bool { get }

    /// The module shows private content: while it is shown the island's
    /// window is hidden from screenshots and screen sharing, for the rest
    /// of that opening and a moment after it closes.
    var excludesFromCapture: Bool { get }

    /// A key press while the module is shown and `takesKeyboard`. Return
    /// whether it was handled (it then goes no further); not offered while
    /// an input method is composing.
    func handleKeyDown(_ event: NSEvent) -> Bool
}

extension IslandModule {
    func suspend() {
        stop()
    }

    func islandDidExpand() {}

    func islandDidCollapse() {}

    var expandedContentHeight: CGFloat { IslandState.defaultContentHeight }

    var expandedWidth: CGFloat { IslandState.expandedWidth }

    var compactContentWidth: CGFloat { IslandStyle.Size.compactContent }

    var tabTitle: String { ModuleKind(rawValue: id)?.title ?? id }

    var tabSymbol: String { ModuleKind(rawValue: id)?.symbol ?? "circle" }

    var takesKeyboard: Bool { false }

    var excludesFromCapture: Bool { false }

    func handleKeyDown(_ event: NSEvent) -> Bool { false }
}

/// A module that takes files dropped on the island (the Shelf). While files
/// are dragged toward the notch, the island opens on this module.
@MainActor
protocol FileDropReceiving: IslandModule {
    func receive(_ files: [DroppedFile])
}
