//
//  IslandController.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import AppKit
import SwiftUI

/// Owns the island panel and keeps it positioned over the notch.
@MainActor
final class IslandController {
    /// Fixed panel size, large enough for the expanded island. Only the
    /// SwiftUI content inside resizes; animating the window frame stutters.
    static let panelSize = CGSize(width: 640, height: 220)

    let state = IslandState()
    private var panel: IslandPanel?

    func start() {
        guard let screen = NotchGeometry.targetScreen() else { return }
        let notch = NotchGeometry.notchRect(for: screen)
        state.notchSize = notch.size

        let frame = NotchGeometry.panelFrame(
            centeredOn: notch,
            screenFrame: screen.frame,
            size: Self.panelSize
        )
        let panel = IslandPanel(contentRect: frame)

        let hostingView = NSHostingView(rootView: IslandView(state: state))
        hostingView.sizingOptions = []  // keep the panel at its fixed size
        panel.contentView = hostingView

        // The panel covers part of the menu bar; let clicks pass through.
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
