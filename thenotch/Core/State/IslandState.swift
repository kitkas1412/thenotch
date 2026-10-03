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
    /// Must fit inside `IslandController.panelSize`.
    var expandedSize = CGSize(width: 520, height: 160)

    let activities = ActivityCenter()
    /// Started modules, in display order.
    var modules: [any IslandModule] = []

    var isExpanded: Bool { mode == .expanded }

    /// Module owning the activity shown in compact mode.
    var currentModule: (any IslandModule)? {
        guard let moduleID = activities.current?.moduleID else { return nil }
        return modules.first { $0.id == moduleID }
    }

    /// Module shown when the island is expanded: the current activity's,
    /// otherwise the first one.
    var expandedModule: (any IslandModule)? {
        currentModule ?? modules.first
    }

    /// Notch size, widened by the wings while an activity is shown.
    var compactSize: CGSize {
        guard currentModule != nil else { return notchSize }
        return CGSize(width: notchSize.width + Self.wingWidth * 2, height: notchSize.height)
    }
}
