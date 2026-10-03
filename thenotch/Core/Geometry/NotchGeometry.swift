//
//  NotchGeometry.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import AppKit

enum NotchGeometry {
    /// Size used to simulate a notch on screens that don't have one.
    static let fallbackWidth: CGFloat = 190
    static let minimumFallbackHeight: CGFloat = 24

    /// Notch rect in screen coordinates. Pure math so it can be unit tested
    /// without a real `NSScreen`.
    ///
    /// - Parameters:
    ///   - frame: `NSScreen.frame`
    ///   - visibleFrame: `NSScreen.visibleFrame`
    ///   - topInset: `NSScreen.safeAreaInsets.top` (0 when there is no notch)
    ///   - leftArea: `NSScreen.auxiliaryTopLeftArea`
    ///   - rightArea: `NSScreen.auxiliaryTopRightArea`
    static func notchRect(
        frame: CGRect,
        visibleFrame: CGRect,
        topInset: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?
    ) -> CGRect {
        if topInset > 0, let leftArea, let rightArea {
            let width = frame.width - leftArea.width - rightArea.width
            if width > 0 {
                return CGRect(
                    x: frame.minX + leftArea.width,
                    y: frame.maxY - topInset,
                    width: width,
                    height: topInset
                )
            }
        }

        // No notch: simulate one centered under the menu bar. The menu bar
        // height is 0 when it auto-hides, hence the minimum.
        let height = max(frame.maxY - visibleFrame.maxY, minimumFallbackHeight)
        return CGRect(
            x: frame.midX - fallbackWidth / 2,
            y: frame.maxY - height,
            width: fallbackWidth,
            height: height
        )
    }

    /// Frame for a panel of `size`, horizontally centered on the notch and
    /// flush with the top edge of the screen.
    static func panelFrame(centeredOn notch: CGRect, screenFrame: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: notch.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func hasNotch(topInset: CGFloat) -> Bool {
        topInset > 0
    }
}

extension NotchGeometry {
    static func notchRect(for screen: NSScreen) -> CGRect {
        notchRect(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
    }

    /// Prefers the built-in notched display, otherwise the main screen.
    @MainActor
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { hasNotch(topInset: $0.safeAreaInsets.top) } ?? NSScreen.main
    }
}
