//
//  IslandState.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import CoreGraphics
import Observation

/// Shared model between `IslandController` and the SwiftUI views.
@MainActor
@Observable
final class IslandState {
    enum Mode {
        case compact, expanded
    }

    /// Width of each "wing" beside the notch while an activity is shown.
    static let wingWidth: CGFloat = 60

    var mode: Mode = .compact
    /// Size of the (real or simulated) notch on the target screen.
    var notchSize = CGSize(width: NotchGeometry.fallbackWidth, height: NotchGeometry.minimumFallbackHeight)

    let activities = ActivityCenter()
    /// Started modules, in display order.
    var modules: [any IslandModule] = []

    var isExpanded: Bool { mode == .expanded }

    /// Files are being dragged and the island is open as a drop target.
    var isDraggingFiles = false
    /// Something is being dragged out of the island; it stays open until
    /// the drag ends.
    var isDraggingOut = false
    /// Called by the views when they start dragging something out; set by
    /// the controller.
    @ObservationIgnored var onDragOutBegan: (() -> Void)?

    /// Module owning the activity shown in compact mode.
    var currentModule: (any IslandModule)? {
        guard let moduleID = activities.current?.moduleID else { return nil }
        return modules.first { $0.id == moduleID }
    }

    /// Module the expanded island stays on while open; set by the controller.
    var pinnedModuleID: String?

    /// Module shown when the island is expanded: the pinned one, else the
    /// current activity's, else the first with something to show. `nil`
    /// when nothing has content: the island then doesn't open on hover.
    var expandedModule: (any IslandModule)? {
        if let pinnedModuleID, let pinned = modules.first(where: { $0.id == pinnedModuleID }) {
            return pinned
        }
        if let currentModule, currentModule.hasExpandedContent {
            return currentModule
        }
        return modules.first { $0.hasExpandedContent }
    }

    static let expandedWidth: CGFloat = 520
    static let defaultExpandedHeight: CGFloat = 160

    /// Size of the open island: each module picks its height (HIG Live
    /// Activities: use only the height the content needs).
    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth, height: expandedModule?.expandedHeight ?? Self.defaultExpandedHeight)
    }

    /// Notch size, widened by the wings while an activity is shown.
    var compactSize: CGSize {
        guard currentModule != nil else { return notchSize }
        return CGSize(width: notchSize.width + Self.wingWidth * 2, height: notchSize.height)
    }
}
