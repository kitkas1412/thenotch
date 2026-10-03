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

    /// Pointer must rest in the entry region this long before opening.
    static let openDelay: Duration = .milliseconds(150)

    let state = IslandState()
    private var panel: IslandPanel?
    /// Notch rect (screen coordinates) on the current target screen.
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    private var pendingOpen: Task<Void, Never>?

    func start() {
        let panel = IslandPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize))

        let hostingView = NSHostingView(rootView: IslandView(state: state))
        hostingView.sizingOptions = []  // keep the panel at its fixed size
        panel.contentView = hostingView

        // The panel covers part of the menu bar; let clicks pass through
        // until the island opens.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        self.panel = panel

        reposition()
        installMouseMonitors()

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
        close(animated: false)
        guard let screen = NotchGeometry.targetScreen() else {
            panel.orderOut(nil)
            return
        }

        notch = NotchGeometry.notchRect(for: screen)
        state.notchSize = notch.size

        let frame = NotchGeometry.panelFrame(
            centeredOn: notch,
            screenFrame: screen.frame,
            size: Self.panelSize
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    // MARK: - Hover

    private func installMouseMonitors() {
        // Global: pointer moves while other apps receive the events (the
        // panel ignores the mouse while compact). No permission needed for
        // mouse events.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mouseMoved()
            }
        }) {
            mouseMonitors.append(global)
        }

        // Local: pointer over our own panel once it accepts mouse events.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.mouseMoved()
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func mouseMoved() {
        let action = HoverPolicy.action(
            isExpanded: state.isExpanded,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            expandedSize: state.expandedSize
        )
        switch action {
        case .open:
            scheduleOpen()
        case .close:
            close(animated: true)
        case .none:
            // Left the entry region before the delay elapsed.
            if !state.isExpanded {
                cancelPendingOpen()
            }
        }
    }

    /// Opens after `openDelay` if the pointer is still in the entry region,
    /// so merely passing over the notch doesn't open the island.
    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        pendingOpen = Task { [weak self] in
            try? await Task.sleep(for: Self.openDelay)
            guard let self, !Task.isCancelled else { return }
            self.pendingOpen = nil
            let stillInside = HoverPolicy.entryRect(notch: self.notch).contains(NSEvent.mouseLocation)
            if stillInside {
                self.open()
            }
        }
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    private func open() {
        guard !state.isExpanded else { return }
        panel?.ignoresMouseEvents = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            state.mode = .expanded
        }
    }

    private func close(animated: Bool) {
        cancelPendingOpen()
        guard state.isExpanded else { return }
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                state.mode = .compact
            }
        } else {
            state.mode = .compact
        }
        panel?.ignoresMouseEvents = true
    }
}
