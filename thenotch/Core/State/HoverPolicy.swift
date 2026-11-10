//
//  HoverPolicy.swift
//  thenotch
//

import CoreGraphics

/// Decides from the pointer position when the compact island grows under
/// it (hover), and when a file drag opens or closes it.
/// Pure math in screen coordinates so it can be unit tested.
///
/// Hovering never opens the island (a click does, and only a click outside,
/// a click on the notch or Esc closes it). Only a file drag opens and closes
/// it by position.
///
/// Every region has hysteresis (the exit region is larger than the entry
/// region), so the island doesn't flicker at an edge.
enum HoverPolicy {
    /// Decision for a file drag (`dragAction`).
    enum Action: Equatable {
        case open, close, none
    }

    /// Decision for the compact island's hover state (`hoverAction`).
    enum HoverAction: Equatable {
        case hover, unhover, none
    }

    /// Tolerance around the notch that counts as "entering".
    static let entryPadding: CGFloat = 6
    /// Tolerance around the expanded island before it closes.
    static let exitPadding: CGFloat = 12
    /// Wider tolerance while files are dragged, so a drag aimed roughly at
    /// the notch opens the island as a drop target.
    static let dragEntryPadding: CGFloat = 40

    /// Compact island (the notch, plus its wings while an activity is
    /// shown) plus `entryPadding` on the sides and bottom.
    static func entryRect(notch: CGRect, compactSize: CGSize) -> CGRect {
        topAnchoredRect(notch: notch, size: compactSize, padding: entryPadding)
    }

    /// Compact island plus `dragEntryPadding`, used while files are dragged.
    static func dragEntryRect(notch: CGRect, compactSize: CGSize) -> CGRect {
        topAnchoredRect(notch: notch, size: compactSize, padding: dragEntryPadding)
    }

    /// Expanded island plus `exitPadding` on the sides and bottom.
    static func exitRect(notch: CGRect, expandedSize: CGSize) -> CGRect {
        topAnchoredRect(notch: notch, size: expandedSize, padding: exitPadding)
    }

    /// Compact island grown by `scale` (anchored at the top) plus
    /// `entryPadding`: the pointer leaves the hover state only outside it, so
    /// the island growing doesn't make the pointer fall off its edge.
    static func hoverExitRect(notch: CGRect, compactSize: CGSize, scale: CGFloat) -> CGRect {
        topAnchoredRect(notch: notch, size: grownSize(compactSize, scale: scale), padding: entryPadding)
    }

    /// `size` scaled by `scale`.
    static func grownSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Hover state for the compact island: starts inside `entryRect`, ends
    /// outside `hoverExitRect`.
    static func hoverAction(
        isHovering: Bool,
        pointer: CGPoint,
        notch: CGRect,
        compactSize: CGSize,
        scale: CGFloat
    ) -> HoverAction {
        if isHovering {
            return hoverExitRect(notch: notch, compactSize: compactSize, scale: scale).contains(pointer) ? .none : .unhover
        }
        return entryRect(notch: notch, compactSize: compactSize).contains(pointer) ? .hover : .none
    }

    /// Whether `pointer` is over an island of `size` centered on the notch
    /// and hanging from the top of the screen (no padding). Used to decide
    /// clicks: on the island, or outside it.
    static func isOnIsland(pointer: CGPoint, notch: CGRect, size: CGSize) -> Bool {
        topAnchoredRect(notch: notch, size: size, padding: 0).contains(pointer)
    }

    /// What a left click does.
    enum ClickAction: Equatable {
        case open, close, none
    }

    /// Decision for a left click at `pointer`.
    ///
    /// Open island: `isBlocked` (a drag or a menu) ignores it; a click
    /// outside the island, or on the notch itself (free of content), closes
    /// it; any other click is the content's (`.none`).
    /// Compact island: a click opens it only while `isHovering` and the
    /// pointer is still within the grown island (`hoverExitRect`), and not
    /// `isBlocked`; otherwise `.none`.
    static func clickAction(
        isExpanded: Bool,
        isHovering: Bool,
        isBlocked: Bool,
        pointer: CGPoint,
        notch: CGRect,
        compactSize: CGSize,
        expandedSize: CGSize,
        scale: CGFloat
    ) -> ClickAction {
        guard !isBlocked else { return .none }
        if isExpanded {
            if !isOnIsland(pointer: pointer, notch: notch, size: expandedSize)
                || isOnIsland(pointer: pointer, notch: notch, size: notch.size) {
                return .close
            }
            return .none
        }
        guard isHovering else { return .none }
        return hoverExitRect(notch: notch, compactSize: compactSize, scale: scale).contains(pointer) ? .open : .none
    }

    /// Decision for a file drag: opens within `dragEntryRect`, and an open
    /// island stays open within its `exitRect` or the drag entry region.
    static func dragAction(
        isExpanded: Bool,
        pointer: CGPoint,
        notch: CGRect,
        compactSize: CGSize,
        expandedSize: CGSize
    ) -> Action {
        if isExpanded {
            // A drag that opened the island keeps it open where it could
            // open it: the island (the shelf's stack) can be narrower than
            // the drag entry region around wide wings.
            let staysOpen = exitRect(notch: notch, expandedSize: expandedSize).contains(pointer)
                || dragEntryRect(notch: notch, compactSize: compactSize).contains(pointer)
            return staysOpen ? .none : .close
        }
        return dragEntryRect(notch: notch, compactSize: compactSize).contains(pointer) ? .open : .none
    }

    /// The open island can shrink under the pointer: clicking the shelf's
    /// tab beside the notch narrows it to the shelf's stack, leaving the
    /// pointer outside. The region the island covered before keeps it open
    /// until the pointer is over the island again (or leaves that region),
    /// so it doesn't close under the click that shrank it.
    struct ShrinkGrace {
        private var lastSize: CGSize?
        private var graceSize: CGSize?

        /// The size whose `exitRect` keeps the island open now.
        /// `isPointerOver` tells whether the pointer is in a size's exit rect.
        mutating func exitSize(for size: CGSize, isPointerOver: (CGSize) -> Bool) -> CGSize {
            if let lastSize, size.width < lastSize.width || size.height < lastSize.height {
                graceSize = Self.union(graceSize ?? lastSize, lastSize)
            }
            lastSize = size
            if graceSize != nil, isPointerOver(size) {
                graceSize = nil
            }
            return graceSize.map { Self.union($0, size) } ?? size
        }

        /// The island closed.
        mutating func reset() {
            self = ShrinkGrace()
        }

        private static func union(_ a: CGSize, _ b: CGSize) -> CGSize {
            CGSize(width: max(a.width, b.width), height: max(a.height, b.height))
        }
    }

    /// Rect of `size` centered on the notch and hanging from the top of the
    /// screen (`notch.maxY`). It extends 1pt above the top so the pointer
    /// pinned at the very top edge still counts as inside.
    private static func topAnchoredRect(notch: CGRect, size: CGSize, padding: CGFloat) -> CGRect {
        CGRect(
            x: notch.midX - size.width / 2 - padding,
            y: notch.maxY - size.height - padding,
            width: size.width + padding * 2,
            height: size.height + padding + 1
        )
    }
}
