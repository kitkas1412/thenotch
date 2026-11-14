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

    let state = IslandState()
    private let settings: AppSettings
    private var panel: IslandPanel?
    /// Between `start()` and `stop()`.
    private var isStarted = false
    /// Bumped by `stop()`, so a pending `observeExpandableContent` doesn't re-arm.
    private var expandableContentGeneration = 0
    /// Notch rect (screen coordinates) on the current target screen.
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var ambientObservers: [(NotificationCenter, NSObjectProtocol)] = []
    /// A menu of ours is open (output picker, a tile's context menu…). The
    /// pointer moving onto it must not close the island under it.
    private var isTrackingMenu = false
    private var mouseMonitors: [Any] = []
    /// Local (clicks on our panel) and global (clicks elsewhere, Esc)
    /// monitors, installed in `installMouseMonitors` / while expanded.
    private var escapeMonitor: Any?
    private var accessibilityObserver: NSObjectProtocol?
    /// A hover re-evaluation after closing is already queued.
    private var isHoverRefreshScheduled = false
    /// Drag pasteboard `changeCount` when the left mouse button went down,
    /// while it's held; see `FileDrag`.
    private var dragChangeCountAtMouseDown: Int?
    /// Ends the drop-target state shortly after the mouse button is released.
    private var pendingDragEnd: Task<Void, Never>?
    /// Polls the mouse button while something is dragged out of the island.
    private var dragOutTask: Task<Void, Never>?
    /// Keeps the island open while it shrinks under the pointer.
    private var shrinkGrace = HoverPolicy.ShrinkGrace()
    /// The island opened by itself for an activity (`LiveActivity.presents`).
    private var presentation: Presentation?

    private struct Presentation {
        let activityID: String
        /// Ends the presentation when the activity expires; an activity
        /// without expiry (a ringing call) lasts until it's removed.
        var closeTask: Task<Void, Never>?
        /// The user clicked the island: it's theirs now and stays open
        /// when the activity ends.
        var isOwnedByUser = false
    }

    /// How long the island stays a drop target after the mouse button is
    /// released: our global monitor sees the mouse-up before the drop
    /// itself reaches the island, and the drop needs its target views.
    static let dropGracePeriod: Duration = .milliseconds(500)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
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

        // Before the modules start: one may present at once.
        state.activities.onPresent = { [weak self] activity in
            self?.present(activity)
        }
        state.activities.onRemove = { [weak self] id in
            guard self?.presentation?.activityID == id else { return }
            self?.endPresentation()
        }
        applyModuleSettings()
        settings.onModulesChange = { [weak self] in
            self?.applyModuleSettings()
        }
        state.onDragOutBegan = { [weak self] in
            self?.dragOutBegan()
        }

        observeMenus()
        observeAmbientConditions()
        observeExpandableContent()
        observeAccessibility()

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

    /// Takes the island down: closes it, removes every monitor and observer,
    /// cancels pending work and suspends the modules (`IslandModule.suspend`).
    /// A later `start()` begins afresh. Does nothing unless started.
    func stop() {
        guard isStarted else { return }
        // Before the modules go: removing their activities must not end a
        // presentation or present.
        state.activities.onPresent = nil
        state.activities.onRemove = nil
        settings.onModulesChange = nil
        state.onDragOutBegan = nil

        close(animated: false)  // ends a presentation, stops the Esc monitor
        isStarted = false

        removeMouseMonitors()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
        for (center, token) in ambientObservers {
            center.removeObserver(token)
        }
        ambientObservers = []
        if let accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(accessibilityObserver)
        }
        accessibilityObserver = nil
        expandableContentGeneration += 1

        pendingDragEnd?.cancel()
        pendingDragEnd = nil
        dragOutTask?.cancel()
        dragOutTask = nil

        for module in state.modules.reversed() {
            module.suspend()
        }
        state.modules = []

        state.mode = .compact
        state.pinnedModuleID = nil
        state.isHovering = false
        state.isDraggingFiles = false
        state.isDraggingOut = false
        state.ambient = AmbientConditions()
        isTrackingMenu = false
        dragChangeCountAtMouseDown = nil
        shrinkGrace.reset()

        if let panel {
            panel.orderOut(nil)
            (panel.contentView as? IslandHostingView<IslandView>)?.onMouseMoved = nil
            panel.contentView = nil
        }
        panel = nil
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
        // The last module with content may be gone under a hovering pointer.
        mouseMoved()
    }

    /// Re-evaluates hover when what the island can show changes (a module's
    /// content or the activities come and go) while the pointer rests on it.
    private func observeExpandableContent() {
        let generation = expandableContentGeneration
        withObservationTracking {
            _ = state.expandedModule
        } onChange: { [weak self] in
            // Fires before the change lands: look after it.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.expandableContentGeneration == generation else { return }
                    self.mouseMoved()
                    self.observeExpandableContent()
                }
            }
        }
    }

    /// Esc needs Accessibility: start its monitor if access is granted
    /// while the island is open.
    private func observeAccessibility() {
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: AccessibilityPermission.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isExpanded else { return }
                self.startEscapeMonitor()
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
                    // Update the hover state if the pointer moved meanwhile.
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

    private func removeMouseMonitors() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors = []
    }

    private func installMouseMonitors() {
        removeMouseMonitors()
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
        // Clicks on other apps' windows (and the menu bar): close the open
        // island when they're outside it. Clicks on our own panel arrive
        // through the local monitor below.
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clickedElsewhere()
            }
        }) {
            mouseMonitors.append(clicks)
        }
        // Clicks on our own panel, which accepts the mouse while the compact
        // island is hovered and while it's open. The event is consumed when
        // it opens or closes the island.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return event }
                return self.clickedPanel() ? nil : event
            }
        }) {
            mouseMonitors.append(local)
        }
        // Over our own panel (once it accepts the mouse) the global monitor
        // sees nothing; IslandHostingView's tracking area reports those moves.
    }

    /// Whether something keeps the island from reacting to the pointer: a
    /// file is being dragged in or out, or one of our menus is open.
    private var isInteractionBlocked: Bool {
        state.isDraggingOut || state.isDraggingFiles || isTrackingMenu
    }

    /// What a click at the pointer does now (`HoverPolicy.clickAction`).
    private func clickAction() -> HoverPolicy.ClickAction {
        HoverPolicy.clickAction(
            isExpanded: state.isExpanded,
            isHovering: state.isHovering,
            isBlocked: isInteractionBlocked,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            compactSize: state.compactSize,
            expandedSize: state.expandedSize,
            scale: IslandStyle.hoverScale
        )
    }

    /// A click on another app (or the menu bar) while the island is open.
    private func clickedElsewhere() {
        guard state.isExpanded, clickAction() == .close else { return }
        close(animated: true)
    }

    /// A click on the panel. Returns whether it was consumed.
    ///
    /// The panel only accepts the mouse while hovered or open. `hitTest`
    /// can't make it click-through (a window that takes the event swallows
    /// it even if no view does), so what is outside the island's shape but
    /// inside the panel is handled here: while open, such a click closes the
    /// island (as does one on the notch); while hovered, the hover region
    /// (island plus a few points) counts as the island. A hovered click
    /// that can't open (nothing left to show) ends the hover. The panel
    /// already accepted this mouse-down, so a click with a stale hover is
    /// swallowed once; setHovering(false) makes the panel click-through
    /// again for the next click.
    private func clickedPanel() -> Bool {
        let wasExpanded = state.isExpanded
        switch clickAction() {
        case .close:
            close(animated: true)
            return true
        case .open:
            open()
            if state.isExpanded { return true }
            setHovering(false)
            return false
        case .none:
            if wasExpanded {
                // The user's now: it stays open when the activity ends.
                presentation?.isOwnedByUser = true
            } else {
                setHovering(false)
            }
            return false
        }
    }

    /// Esc closes the open island. The panel never becomes key, so a local
    /// key monitor would never fire; a global one needs Accessibility, so
    /// without it Esc does nothing (clicks still close the island).
    private func startEscapeMonitor() {
        guard escapeMonitor == nil, AccessibilityPermission.isTrusted else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated {
                guard let self, self.state.isExpanded, !self.isInteractionBlocked else { return }
                self.close(animated: true)
            }
        }
    }

    private func stopEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    /// Tracks the pointer over the compact island: it grows (hover) and
    /// takes the mouse so a click opens it. Never opens or closes by itself.
    private func mouseMoved() {
        guard isStarted, !state.isExpanded else { return }
        let canHover = state.expandedModule != nil && !isInteractionBlocked
        let action = HoverPolicy.hoverAction(
            isHovering: state.isHovering,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            compactSize: state.compactSize,
            scale: IslandStyle.hoverScale
        )
        switch action {
        case .hover where canHover:
            setHovering(true)
        case .unhover:
            setHovering(false)
        default:
            // Something now blocks hovering, or has nothing to show.
            if state.isHovering && !canHover {
                setHovering(false)
            }
        }
    }

    private func setHovering(_ hovering: Bool) {
        guard state.isHovering != hovering else { return }
        state.isHovering = hovering
        panel?.ignoresMouseEvents = !hovering
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
        let action = HoverPolicy.dragAction(
            isExpanded: state.isExpanded,
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
    /// stays open if the pointer is still where it opens, else closes.
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
            self.closeIfDragLeft()
        }
    }

    /// A view started dragging something out of the island. SwiftUI owns
    /// the drag session (`NSHostingView` doesn't let subclasses see it
    /// end), and our own drag's events reach neither monitor, so poll the
    /// mouse button until it's released.
    private func dragOutBegan() {
        guard !state.isDraggingOut else { return }
        state.isDraggingOut = true
        dragOutTask = Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            self.dragOutTask = nil
            self.state.isDraggingOut = false
            self.mouseMoved()
        }
    }

    /// After a file drag, closes the island if the pointer isn't where the
    /// drag would keep it open.
    private func closeIfDragLeft() {
        guard state.isExpanded, presentation == nil else { return }
        let action = HoverPolicy.dragAction(
            isExpanded: true,
            pointer: NSEvent.mouseLocation,
            notch: notch,
            compactSize: state.compactSize,
            expandedSize: exitSize()
        )
        if action == .close {
            close(animated: true)
        }
    }

    /// Opens on `moduleID`, or on the module `IslandState.expandedModule`
    /// picks.
    private func open(pinning moduleID: String? = nil) {
        guard !state.isExpanded else { return }
        // An island with nothing to show (no music, empty shelf…) stays
        // closed; a file drag or a presentation always pins its module.
        guard moduleID != nil || state.expandedModule != nil else { return }
        state.isHovering = false
        panel?.ignoresMouseEvents = false
        // Keep showing this module while open, even if another activity
        // (e.g. a battery peek) takes over the compact island meanwhile.
        state.pinnedModuleID = moduleID ?? state.expandedModule?.id
        withAnimation(IslandStyle.openAnimation) {
            state.mode = .expanded
        }
        state.expandedModule?.islandDidExpand()
        startEscapeMonitor()
    }

    /// Opens the island on the activity's module until it expires. Doesn't
    /// take over an island the user opened, a drag or an open menu, nor open
    /// while nobody can see it.
    private func present(_ activity: LiveActivity) {
        guard state.ambient.isVisible, !state.isDraggingFiles, !state.isDraggingOut, !isTrackingMenu else { return }
        // A brief activity doesn't cut a lasting one short (a notification
        // arriving while a call rings).
        if let presentation, presentation.closeTask == nil, activity.expiresAt != nil { return }
        if state.isExpanded {
            guard presentation != nil else { return }
            state.select(activity.moduleID)
        } else {
            open(pinning: activity.moduleID)
            guard state.isExpanded else { return }
        }
        let isOwnedByUser = presentation?.isOwnedByUser ?? false
        presentation?.closeTask?.cancel()
        let closeTask = activity.expiresAt.map { expiresAt in
            let duration = max(expiresAt.timeIntervalSinceNow, 1)
            return Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self, !Task.isCancelled else { return }
                self.endPresentation()
            }
        }
        presentation = Presentation(activityID: activity.id, closeTask: closeTask, isOwnedByUser: isOwnedByUser)
    }

    /// The presented activity ended: the island closes, unless the user
    /// clicked it meanwhile — from then on, they close it.
    private func endPresentation() {
        presentation?.closeTask?.cancel()
        let isOwnedByUser = presentation?.isOwnedByUser ?? false
        presentation = nil
        if !isOwnedByUser {
            close(animated: true)
        }
    }

    private func close(animated: Bool) {
        presentation?.closeTask?.cancel()
        presentation = nil
        stopEscapeMonitor()
        state.isHovering = false
        guard state.isExpanded else {
            panel?.ignoresMouseEvents = true
            return
        }
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
        // The pointer may rest on the notch: show the hover cue without
        // waiting for it to move.
        if !isHoverRefreshScheduled {
            isHoverRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.isHoverRefreshScheduled = false
                    self?.mouseMoved()
                }
            }
        }
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
