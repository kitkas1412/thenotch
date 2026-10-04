//
//  IslandController.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import AppKit
import os
import SwiftUI

/// Owns the island panel and keeps it positioned over the notch.
@MainActor
final class IslandController {
    /// Fixed panel size, large enough for the expanded island. Only the
    /// SwiftUI content inside resizes; animating the window frame stutters.
    static let panelSize = CGSize(width: 640, height: 320)

    /// Pointer must rest in the entry region this long before opening.
    static let openDelay: Duration = .milliseconds(150)

    let state = IslandState()
    private let settings: AppSettings
    private var panel: IslandPanel?
    /// Notch rect (screen coordinates) on the current target screen.
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var ambientObservers: [(NotificationCenter, NSObjectProtocol)] = []
    /// A menu of ours is open (output picker, a tile's context menu…). The
    /// pointer moving onto it must not close the island under it.
    private var isTrackingMenu = false
    private var mouseMonitors: [Any] = []
    private var pendingOpen: Task<Void, Never>?
    /// Drag pasteboard `changeCount` when the left mouse button went down,
    /// while it's held; see `FileDrag`.
    private var dragChangeCountAtMouseDown: Int?
    /// Ends the drop-target state shortly after the mouse button is released.
    private var pendingDragEnd: Task<Void, Never>?
    /// Keeps the island open while it shrinks under the pointer.
    private var shrinkGrace = HoverPolicy.ShrinkGrace()
    /// The island opened by itself for an activity (`LiveActivity.presents`).
    private var presentation: Presentation?

    private struct Presentation {
        /// Closes the island when the activity ends, unless the pointer
        /// came over it: from then on, hovering decides.
        var closeTask: Task<Void, Never>
        var hasPointerEntered = false
    }

    /// How long the island stays a drop target after the mouse button is
    /// released: our global monitor sees the mouse-up before the drop
    /// itself reaches the island, and the drop needs its target views.
    static let dropGracePeriod: Duration = .milliseconds(500)

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
        state.onDragOutBegan = { [weak self] in
            self?.dragOutBegan()
        }
        state.activities.onPresent = { [weak self] activity in
            self?.present(activity)
        }

        observeMenus()
        observeAmbientConditions()

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
            let module = kind.makeModule(activities: state.activities, settings: settings)
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

    private func observeMenus() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isTrackingMenu = true
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isTrackingMenu = false
                    // Close now if the pointer left while the menu was up.
                    self.mouseMoved()
                }
            },
        ]
    }

    /// Keeps `state.ambient` current, so ambient animation stops while
    /// nobody sees it or Low Power Mode is on.
    private func observeAmbientConditions() {
        state.ambient.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let workspace = NSWorkspace.shared.notificationCenter
        observeAmbient(workspace, NSWorkspace.screensDidSleepNotification) { $0.isDisplayAsleep = true }
        observeAmbient(workspace, NSWorkspace.screensDidWakeNotification) { $0.isDisplayAsleep = false }
        observeAmbient(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observeAmbient(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }
        // Posted by loginwindow; there's no public API for the lock state.
        let distributed = DistributedNotificationCenter.default()
        observeAmbient(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observeAmbient(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }
        observeAmbient(.default, Notification.Name.NSProcessInfoPowerStateDidChange) {
            $0.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func observeAmbient(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        update: @escaping @MainActor (inout AmbientConditions) -> Void
    ) {
        // `NSProcessInfoPowerStateDidChange` may arrive on any thread; the
        // `.main` queue delivers it on the main thread.
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var ambient = self.state.ambient
                update(&ambient)
                if ambient != self.state.ambient {
                    self.state.ambient = ambient
                }
            }
        }
        ambientObservers.append((center, token))
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
        // Dragging a file out of the island, or a menu is open: stay open
        // until it's done.
        if state.isDraggingOut || isTrackingMenu { return }
        // Opened by itself: the pointer elsewhere doesn't close it, the end
        // of the activity does — until the pointer comes over it.
        if presentation != nil, state.isExpanded {
            if HoverPolicy.exitRect(notch: notch, expandedSize: state.expandedSize).contains(NSEvent.mouseLocation) {
                presentation?.hasPointerEntered = true
            } else if presentation?.hasPointerEntered == false {
                return
            }
        }
        let action = HoverPolicy.action(
            isExpanded: state.isExpanded,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            compactSize: state.compactSize,
            expandedSize: exitSize()
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

    /// The open island's size for the exit test, kept larger for a moment
    /// after it shrinks under the pointer (`HoverPolicy.ShrinkGrace`).
    private func exitSize() -> CGSize {
        guard state.isExpanded else { return state.expandedSize }
        let pointer = NSEvent.mouseLocation
        return shrinkGrace.exitSize(for: state.expandedSize) { [notch] size in
            HoverPolicy.exitRect(notch: notch, expandedSize: size).contains(pointer)
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
            expandedSize: exitSize()
        )
        if action == .close {
            close(animated: true)
            return
        }
        // Near the notch, or over the open island. The pasteboard is only
        // checked there, so ordinary drags elsewhere cost a rect test.
        guard action == .open || state.isExpanded else { return }
        guard state.isDraggingFiles || isFileDrag(since: changeCountAtMouseDown) else { return }
        pendingDragEnd?.cancel()
        pendingDragEnd = nil
        if !state.isDraggingFiles {
            Log.drop.notice("File drag reached the notch; opening as a drop target")
        }
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
            carriesFiles: FileDrag.carriesFiles(
                pasteboard.types?.map(\.rawValue) ?? [],
                promiseTypes: NSFilePromiseReceiver.readableDraggedTypes
            )
        )
    }

    /// The drag finished (dropped on the island or elsewhere). The island
    /// stays open if the pointer is still over it, then closes on hover exit.
    ///
    /// The drop zones must outlive the mouse-up: removing them right away
    /// left the drop, which arrives a moment later, with nowhere to land.
    private func dragEnded() {
        dragChangeCountAtMouseDown = nil
        guard state.isDraggingFiles, pendingDragEnd == nil else { return }
        Log.drop.debug("Mouse released; keeping drop targets for the grace period")
        pendingDragEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.dropGracePeriod)
            guard let self, !Task.isCancelled else { return }
            self.pendingDragEnd = nil
            self.state.isDraggingFiles = false
            self.mouseMoved()
        }
    }

    /// A view started dragging something out of the island. SwiftUI owns
    /// the drag session (`NSHostingView` doesn't let subclasses see it
    /// end), and our own drag's events reach neither monitor, so poll the
    /// mouse button until it's released.
    private func dragOutBegan() {
        guard !state.isDraggingOut else { return }
        state.isDraggingOut = true
        Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self else { return }
            self.state.isDraggingOut = false
            self.mouseMoved()
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
        // Hovering an island with nothing to show (no music, empty shelf…)
        // leaves the notch alone; a file drag always pins its module.
        guard moduleID != nil || state.expandedModule != nil else { return }
        panel?.ignoresMouseEvents = false
        // Keep showing this module while open, even if another activity
        // (e.g. a battery peek) takes over the compact island meanwhile.
        state.pinnedModuleID = moduleID ?? state.expandedModule?.id
        withAnimation(IslandStyle.openAnimation) {
            state.mode = .expanded
        }
        state.expandedModule?.islandDidExpand()
    }

    /// Opens the island on the activity's module until it expires. Doesn't
    /// take over an island the user opened, a drag or an open menu, nor open
    /// while nobody can see it.
    private func present(_ activity: LiveActivity) {
        guard state.ambient.isVisible, !state.isDraggingFiles, !state.isDraggingOut, !isTrackingMenu else { return }
        if state.isExpanded {
            guard presentation != nil else { return }
            state.select(activity.moduleID)
        } else {
            open(pinning: activity.moduleID)
            guard state.isExpanded else { return }
        }
        let hasPointerEntered = presentation?.hasPointerEntered ?? false
        presentation?.closeTask.cancel()
        let duration = max(activity.expiresAt?.timeIntervalSinceNow ?? 0, 1)
        let closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            let hovered = self.presentation?.hasPointerEntered ?? false
            self.presentation = nil
            if hovered {
                self.mouseMoved()
            } else {
                self.close(animated: true)
            }
        }
        presentation = Presentation(closeTask: closeTask, hasPointerEntered: hasPointerEntered)
    }

    private func close(animated: Bool) {
        presentation?.closeTask.cancel()
        presentation = nil
        cancelPendingOpen()
        guard state.isExpanded else { return }
        if animated {
            withAnimation(IslandStyle.closeAnimation) {
                state.mode = .compact
            }
        } else {
            state.mode = .compact
        }
        state.pinnedModuleID = nil
        shrinkGrace.reset()
        for module in state.modules {
            module.islandDidCollapse()
        }
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
