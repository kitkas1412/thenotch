//
//  WindowLayout.swift
//  thenotch
//

import Carbon.HIToolbox
import CoreGraphics

/// A way to place the focused window.
enum WindowAction: String, CaseIterable, Identifiable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, center
    case nextDisplay, previousDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        }
    }

    /// Whether the window goes to another display.
    var changesDisplay: Bool { self == .nextDisplay || self == .previousDisplay }

    var defaultShortcut: Shortcut {
        let control: Shortcut.Modifiers = [.control, .option]
        func make(_ key: Int, _ modifiers: Shortcut.Modifiers = [.control, .option]) -> Shortcut {
            Shortcut(keyCode: UInt32(key), modifiers: modifiers)
        }
        switch self {
        case .leftHalf: return make(kVK_LeftArrow)
        case .rightHalf: return make(kVK_RightArrow)
        case .topHalf: return make(kVK_UpArrow)
        case .bottomHalf: return make(kVK_DownArrow)
        case .topLeft: return make(kVK_ANSI_U)
        case .topRight: return make(kVK_ANSI_I)
        case .bottomLeft: return make(kVK_ANSI_J)
        case .bottomRight: return make(kVK_ANSI_K)
        case .firstThird: return make(kVK_ANSI_D)
        case .centerThird: return make(kVK_ANSI_F)
        case .lastThird: return make(kVK_ANSI_G)
        case .firstTwoThirds: return make(kVK_ANSI_E)
        case .lastTwoThirds: return make(kVK_ANSI_T)
        case .maximize: return make(kVK_Return)
        case .center: return make(kVK_ANSI_C)
        case .nextDisplay: return make(kVK_RightArrow, control.union(.command))
        case .previousDisplay: return make(kVK_LeftArrow, control.union(.command))
        }
    }
}

/// Window placement as pure functions on plain values. `frame`s and
/// `visibleFrame`s are in Cocoa coordinates (origin bottom left) unless a
/// function says otherwise.
enum WindowLayout {
    /// The window's new frame on its display, `nil` for the display actions
    /// (see `movedToDisplay`).
    static func frame(for action: WindowAction, windowFrame: CGRect, visibleFrame area: CGRect) -> CGRect? {
        let minX = area.minX, minY = area.minY
        let w = area.width, h = area.height
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            integral(CGRect(x: minX + x, y: minY + y, width: width, height: height))
        }
        switch action {
        case .leftHalf: return rect(0, 0, w / 2, h)
        case .rightHalf: return rect(w / 2, 0, w / 2, h)
        case .topHalf: return rect(0, h / 2, w, h / 2)
        case .bottomHalf: return rect(0, 0, w, h / 2)
        case .topLeft: return rect(0, h / 2, w / 2, h / 2)
        case .topRight: return rect(w / 2, h / 2, w / 2, h / 2)
        case .bottomLeft: return rect(0, 0, w / 2, h / 2)
        case .bottomRight: return rect(w / 2, 0, w / 2, h / 2)
        case .firstThird: return rect(0, 0, w / 3, h)
        case .centerThird: return rect(w / 3, 0, w / 3, h)
        case .lastThird: return rect(w * 2 / 3, 0, w / 3, h)
        case .firstTwoThirds: return rect(0, 0, w * 2 / 3, h)
        case .lastTwoThirds: return rect(w / 3, 0, w * 2 / 3, h)
        case .maximize: return integral(area)
        case .center:
            let width = min(windowFrame.width, w), height = min(windowFrame.height, h)
            return integral(CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height))
        case .nextDisplay, .previousDisplay: return nil
        }
    }

    /// The window on another display: same relative position and size, or
    /// the whole visible area if it doesn't fit there.
    static func movedToDisplay(windowFrame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0,
              windowFrame.width <= target.width, windowFrame.height <= target.height
        else { return integral(target) }
        let scaleX = target.width / source.width, scaleY = target.height / source.height
        let width = min(windowFrame.width * scaleX, target.width)
        let height = min(windowFrame.height * scaleY, target.height)
        var x = target.minX + (windowFrame.minX - source.minX) * scaleX
        var y = target.minY + (windowFrame.minY - source.minY) * scaleY
        x = min(max(x, target.minX), target.maxX - width)
        y = min(max(y, target.minY), target.maxY - height)
        return integral(CGRect(x: x, y: y, width: width, height: height))
    }

    /// The next or previous display index, wrapping; `current` stays put
    /// with a single display.
    static func targetScreenIndex(current: Int, count: Int, forward: Bool) -> Int {
        guard count > 1 else { return max(current, 0) }
        return ((current + (forward ? 1 : -1)) % count + count) % count
    }

    /// The index of the screen frame the rect overlaps most; with no
    /// overlap, the one whose center is nearest. `nil` without screens.
    static func screenIndex(containing rect: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        if let best { return best.index }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func distance(_ screen: CGRect) -> CGFloat {
            hypot(screen.midX - center.x, screen.midY - center.y)
        }
        return screens.indices.min { distance(screens[$0]) < distance(screens[$1]) }
    }

    /// AX coordinates (origin top left of the primary display, y down) to
    /// Cocoa (origin bottom left of the primary display). `primaryHeight` is
    /// the height of the screen whose origin is `.zero`.
    static func axToCocoa(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    /// The inverse of `axToCocoa`; the formula is its own inverse.
    static func cocoaToAX(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        axToCocoa(rect, primaryHeight: primaryHeight)
    }

    private static func integral(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }
}
