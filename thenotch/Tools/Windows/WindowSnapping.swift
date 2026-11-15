//
//  WindowSnapping.swift
//  thenotch
//

import CoreGraphics
import Foundation

/// A display for snap detection, in Cocoa coordinates.
struct SnapScreen: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
}

/// Where a dragged window lands when released at a screen edge or corner.
enum SnapArea: Equatable, CaseIterable {
    case left, right, top
    case topLeft, topRight, bottomLeft, bottomRight

    var action: WindowAction {
        switch self {
        case .left: .leftHalf
        case .right: .rightHalf
        case .top: .maximize
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }

    /// The area under the pointer, in Cocoa coordinates, with the index of
    /// its screen in `screens`. Uses each screen's `frame` (where the
    /// pointer physically stops). Corners win over edges; the bottom edge
    /// alone doesn't snap; an edge shared with another screen (abutting
    /// within 1 pt) doesn't snap over the span they overlap.
    static func detect(
        cursor: CGPoint,
        screens: [SnapScreen],
        edgeMargin: CGFloat = 4,
        cornerSize: CGFloat = 24
    ) -> (area: SnapArea, screenIndex: Int)? {
        let index = screens.firstIndex { $0.frame.contains(cursor) }
            ?? screens.firstIndex { $0.frame.insetBy(dx: -1, dy: -1).contains(cursor) }
        guard let index else { return nil }
        let frame = screens[index].frame
        let others = screens.indices.filter { $0 != index }.map { screens[$0].frame }

        func within(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> Bool {
            value >= low - 1 && value <= high + 1
        }
        let leftShared = others.contains { abs($0.maxX - frame.minX) <= 1 && within(cursor.y, $0.minY, $0.maxY) }
        let rightShared = others.contains { abs($0.minX - frame.maxX) <= 1 && within(cursor.y, $0.minY, $0.maxY) }
        let topShared = others.contains { abs($0.minY - frame.maxY) <= 1 && within(cursor.x, $0.minX, $0.maxX) }
        let bottomShared = others.contains { abs($0.maxY - frame.minY) <= 1 && within(cursor.x, $0.minX, $0.maxX) }

        let dLeft = cursor.x - frame.minX, dRight = frame.maxX - cursor.x
        let dTop = frame.maxY - cursor.y, dBottom = cursor.y - frame.minY

        let touchLeft = dLeft <= edgeMargin && !leftShared
        let touchRight = dRight <= edgeMargin && !rightShared
        let touchTop = dTop <= edgeMargin && !topShared
        let touchBottom = dBottom <= edgeMargin && !bottomShared

        // Corners: within `cornerSize` of the corner on both axes while
        // touching one of its edges.
        let nearLeft = dLeft <= cornerSize && !leftShared
        let nearRight = dRight <= cornerSize && !rightShared
        let nearTop = dTop <= cornerSize && !topShared
        let nearBottom = dBottom <= cornerSize && !bottomShared
        let touching = touchLeft || touchRight || touchTop || touchBottom
        if touching {
            if nearTop && nearLeft { return (.topLeft, index) }
            if nearTop && nearRight { return (.topRight, index) }
            if nearBottom && nearLeft { return (.bottomLeft, index) }
            if nearBottom && nearRight { return (.bottomRight, index) }
        }
        if touchTop { return (.top, index) }
        if touchLeft { return (.left, index) }
        if touchRight { return (.right, index) }
        return nil
    }
}

/// What a drag did to the window, from its frame at the start and now (same
/// coordinate space).
enum DragMotion: Equatable {
    case moved, resized, unchanged

    static func classify(start: CGRect, current: CGRect) -> DragMotion {
        let sizeSame = abs(current.width - start.width) <= 1 && abs(current.height - start.height) <= 1
        let originChanged = abs(current.minX - start.minX) > 1 || abs(current.minY - start.minY) > 1
        if !sizeSame { return .resized }
        return originChanged ? .moved : .unchanged
    }
}

/// Dragging a snapped window away gives it back its size from before the
/// snap.
enum SnapRestore {
    /// Whether a window first read at `observed`, after the pointer moved
    /// `slack` pt from where the mouse went down, is still the snapped
    /// window: same size (±2 pt), origin within 2 pt plus the drag so far.
    static func matches(snappedFrame: CGRect, observed: CGRect, slack: CGFloat) -> Bool {
        let tolerance: CGFloat = 2
        return abs(observed.width - snappedFrame.width) <= tolerance
            && abs(observed.height - snappedFrame.height) <= tolerance
            && abs(observed.minX - snappedFrame.minX) <= tolerance + slack
            && abs(observed.minY - snappedFrame.minY) <= tolerance + slack
    }

    /// The window's frame at `originalSize`, keeping the grab point (where
    /// the mouse went down on the snapped frame) at the same proportion of
    /// the window under `cursor`. `nil` for empty sizes. Same coordinate
    /// space for all, y up.
    static func frame(
        originalSize: CGSize,
        snappedFrame: CGRect,
        grab: CGPoint,
        cursor: CGPoint
    ) -> CGRect? {
        guard snappedFrame.width > 0, snappedFrame.height > 0,
              originalSize.width > 0, originalSize.height > 0
        else { return nil }
        let fx = min(max((grab.x - snappedFrame.minX) / snappedFrame.width, 0), 1)
        let fyFromTop = min(max((snappedFrame.maxY - grab.y) / snappedFrame.height, 0), 1)
        let x = cursor.x - fx * originalSize.width
        let maxY = cursor.y + fyFromTop * originalSize.height
        return CGRect(x: x.rounded(), y: (maxY - originalSize.height).rounded(),
                      width: originalSize.width, height: originalSize.height)
    }
}

/// macOS 15's own tiling by dragging to an edge.
enum NativeTiling {
    static let edgeDragKey = "EnableTilingByEdgeDrag"
    static let topEdgeDragKey = "EnableTopTilingByEdgeDrag"
    static let domain = "com.apple.WindowManager"

    /// Off before macOS 15. A key is only written once the user changes its
    /// switch, and the system default is on. True if either the edge or the
    /// top-edge tiling is on.
    static func isEdgeDragEnabled(values: [String: Any], osMajor: Int) -> Bool {
        guard osMajor >= 15 else { return false }
        return [edgeDragKey, topEdgeDragKey].contains { (values[$0] as? Bool) ?? true }
    }

    /// Reads the preferences (read-only).
    static func isEdgeDragCurrentlyEnabled() -> Bool {
        var values: [String: Any] = [:]
        for key in [edgeDragKey, topEdgeDragKey] {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) {
                values[key] = value
            }
        }
        return isEdgeDragEnabled(values: values, osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}
