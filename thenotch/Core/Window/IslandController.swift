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
    private let settings: AppSettings
    private var panel: IslandPanel?
    /// Notch rect (screen coordinates) on the current target screen.
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    private var pendingOpen: Task<Void, Never>?
    /// Drag pasteboard `changeCount` when the left mouse button went down,
    /// while it's held; see `FileDrag`.
    private var dragChangeCountAtMouseDown: Int?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        let panel = IslandPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize))

        let hostingView = IslandHostingView(rootView: IslandView(state: state))
        hostingView.sizingOptions = []  // keep the panel at its fixed size
        hostingView.onMouseMoved = { [weak self] in
            self?.mouseMoved()
        }
        panel.contentView = hostingView

        // The panel covers part of the menu bar; let clicks pass through
        // until the island opens.
        panel.ignoresMouseEvents = true
        self.panel = panel

        reposition()
        installMouseMonitors()

        applyModuleSettings()
        settings.onModulesChange = { [weak self] in
            self?.applyModuleSettings()
        }

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

    /// Starts newly enabled modules and stops disabled ones, keeping
    /// `ModuleKind` order. A disabled module is never started.
    private func applyModuleSettings() {
        let enabled = settings.enabledModules
        for module in state.modules where !enabled.contains(where: { $0.id == module.id }) {
            module.stop()
        }
        state.modules = enabled.map { kind in
            if let running = state.modules.first(where: { $0.id == kind.id }) {
                return running
            }
            let module = kind.makeModule(activities: state.activities)
            module.start()
            return module
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
        // Files dragged from other apps (Finder…) toward the notch. Drags
        // send these instead of `mouseMoved`.
        if let drags = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                self?.mouseDragEvent(type)
            }
        }) {
            mouseMonitors.append(drags)
        }
        // Over our own panel (once it accepts the mouse) the global monitor
        // sees nothing; IslandHostingView's tracking area reports those moves.
    }

    private func mouseMoved() {
        let action = HoverPolicy.action(
            isExpanded: state.isExpanded,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            compactSize: state.compactSize,
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

    // MARK: - Dragging files

    /// Module that takes dropped files, if one is enabled.
    private var fileDropModule: (any FileDropReceiving)? {
        state.modules.lazy.compactMap { $0 as? any FileDropReceiving }.first
    }

    private func mouseDragEvent(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            // Only read the pasteboard if a drop could be taken.
            dragChangeCountAtMouseDown = fileDropModule == nil ? nil : NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            mouseDragged()
        case .leftMouseUp:
            dragEnded()
        default:
            break
        }
    }

    private func mouseDragged() {
        guard let changeCountAtMouseDown = dragChangeCountAtMouseDown, let target = fileDropModule else { return }
        let action = HoverPolicy.action(
            isExpanded: state.isExpanded,
            isDragging: true,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            compactSize: state.compactSize,
            expandedSize: state.expandedSize
        )
        if action == .close {
            close(animated: true)
            return
        }
        // Near the notch, or over the open island. The pasteboard is only
        // checked there, so ordinary drags elsewhere cost a rect test.
        guard action == .open || state.isExpanded else { return }
        guard state.isDraggingFiles || isFileDrag(since: changeCountAtMouseDown) else { return }
        state.isDraggingFiles = true
        if !state.isExpanded {
            open(pinning: target.id)
        } else if state.pinnedModuleID != target.id {
            state.pinnedModuleID = target.id
            target.islandDidExpand()
        }
    }

    private func isFileDrag(since changeCountAtMouseDown: Int) -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return FileDrag.isFileDrag(
            changeCount: pasteboard.changeCount,
            changeCountAtMouseDown: changeCountAtMouseDown,
            hasFileURLs: pasteboard.types?.contains(.fileURL) ?? false
        )
    }

    /// The drag finished (dropped on the island or elsewhere). The island
    /// stays open if the pointer is still over it, then closes on hover exit.
    private func dragEnded() {
        dragChangeCountAtMouseDown = nil
        guard state.isDraggingFiles else { return }
        state.isDraggingFiles = false
        state.isDropTargeted = false
        mouseMoved()
    }

    /// Opens after `openDelay` if the pointer is still in the entry region,
    /// so merely passing over the notch doesn't open the island.
    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        pendingOpen = Task { [weak self] in
            try? await Task.sleep(for: Self.openDelay)
            guard let self, !Task.isCancelled else { return }
            self.pendingOpen = nil
            let stillInside = HoverPolicy.entryRect(notch: self.notch, compactSize: self.state.compactSize).contains(NSEvent.mouseLocation)
            if stillInside {
                self.open()
            }
        }
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    /// Opens on `moduleID`, or on the module `IslandState.expandedModule`
    /// picks.
    private func open(pinning moduleID: String? = nil) {
        cancelPendingOpen()
        guard !state.isExpanded else { return }
        panel?.ignoresMouseEvents = false
        // Keep showing this module while open, even if another activity
        // (e.g. a battery peek) takes over the compact island meanwhile.
        state.pinnedModuleID = moduleID ?? state.expandedModule?.id
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            state.mode = .expanded
        }
        state.expandedModule?.islandDidExpand()
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
        state.pinnedModuleID = nil
        panel?.ignoresMouseEvents = true
    }
}

/// Hosting view for the island panel, which never becomes key:
/// - accepts the first click, which would otherwise be swallowed;
/// - reports mouse moves via an always-active tracking area, because
///   AppKit only sends `mouseMoved` to the key window.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseMoved: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.options.contains(.activeAlways) }) {
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseMoved?()
    }
}
