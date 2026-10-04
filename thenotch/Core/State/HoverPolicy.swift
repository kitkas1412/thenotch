//
//  HoverPolicy.swift
//  thenotch
//

import CoreGraphics

/// Decides when the island opens or closes from the pointer position.
/// Pure math in screen coordinates so it can be unit tested.
///
/// The exit region is larger than the entry region (hysteresis), so the
/// island doesn't flicker open/closed when the pointer sits on an edge.
enum HoverPolicy {
    enum Action: Equatable {
        case open, close, none
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

    static func action(
        isExpanded: Bool,
        isDragging: Bool = false,
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
                || (isDragging && dragEntryRect(notch: notch, compactSize: compactSize).contains(pointer))
            return staysOpen ? .none : .close
        }
        let entry = isDragging
            ? dragEntryRect(notch: notch, compactSize: compactSize)
            : entryRect(notch: notch, compactSize: compactSize)
        return entry.contains(pointer) ? .open : .none
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
