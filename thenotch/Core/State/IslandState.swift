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
    /// Content height when a module doesn't pick one (or none is shown):
    /// fits an `IslandEmptyState`.
    static let defaultContentHeight: CGFloat = IslandEmptyState.contentHeight

    /// Size of the open island: the notch, the margin below it, then the
    /// shown module's content, which picks its own height (HIG Live
    /// Activities: use only the height the content needs). Adding the
    /// notch keeps content clear of it on every Mac.
    var expandedSize: CGSize {
        let content = expandedModule?.expandedContentHeight ?? Self.defaultContentHeight
        return CGSize(width: Self.expandedWidth, height: notchSize.height + IslandStyle.Spacing.content + content)
    }

    /// Notch size, widened by the wings while an activity is shown.
    var compactSize: CGSize {
        guard currentModule != nil else { return notchSize }
        return CGSize(width: notchSize.width + wingWidth * 2, height: notchSize.height)
    }

    /// Equal padding in the compact island: wing content is
    /// `IslandStyle.Size.compactContent` tall, centered in the notch's
    /// height, and has that same padding on its other sides — toward the
    /// notch and toward the island's outer edge.
    var compactPadding: CGFloat {
        max(0, (notchSize.height - IslandStyle.Size.compactContent) / 2)
    }

    /// Width of each wing beside the notch: the shown module's content
    /// with the compact padding on both sides. Both wings share it, so
    /// the island stays centered on the notch.
    var wingWidth: CGFloat {
        (currentModule?.compactContentWidth ?? IslandStyle.Size.compactContent) + compactPadding * 2
    }

    /// Bottom corner radius of the compact island: the bare notch's, or
    /// with wings, concentric with their content (its corner radius plus
    /// the padding).
    var compactCornerRadius: CGFloat {
        currentModule == nil ? IslandStyle.Radius.compact : IslandStyle.Radius.small + compactPadding
    }
}
