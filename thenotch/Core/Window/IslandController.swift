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
    private var screenObserver: NSObjectProtocol?

    func start() {
        let panel = IslandPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize))

        let hostingView = NSHostingView(rootView: IslandView(state: state))
        hostingView.sizingOptions = []  // keep the panel at its fixed size
        panel.contentView = hostingView

        // The panel covers part of the menu bar; let clicks pass through.
        panel.ignoresMouseEvents = true
        self.panel = panel

        reposition()

        // Displays plugged/unplugged, resolution or arrangement changed.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        }
    }

    /// Moves the panel onto the current target screen and resizes the
    /// island to that screen's notch. Hides the panel if there is no screen.
    private func reposition() {
        guard let panel else { return }
        guard let screen = NotchGeometry.targetScreen() else {
            panel.orderOut(nil)
            return
        }

        let notch = NotchGeometry.notchRect(for: screen)
        state.notchSize = notch.size

        let frame = NotchGeometry.panelFrame(
            centeredOn: notch,
            screenFrame: screen.frame,
            size: Self.panelSize
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
}
