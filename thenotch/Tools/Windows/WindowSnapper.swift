//
//  WindowSnapper.swift
//  thenotch
//

import AppKit
import os

/// Snaps another app's window while it is dragged to a screen edge or
/// corner: a preview shows the target, releasing the mouse places the window.
/// Global mouse monitors only; the Accessibility lookup happens once the
/// drag starts (never on every click), and any failed call abandons the
/// gesture silently.
@MainActor
final class WindowSnapper {
    private struct Gesture {
        /// Where the mouse went down, Cocoa coordinates.
        let grab: CGPoint
        let startedAt = Date()
        var window: AXWindow?
        /// The tracked window's frame and the pointer when first read.
        var startFrame: CGRect?
        var startCursor: CGPoint = .zero
        var lookups = 0
        var lastRead = Date.distantPast
        var isMove = false
        var abandoned = false
        var originalSize: CGSize?
        var pendingRestore: Record?
        var restoreTries = 0
        var target: (area: SnapArea, frame: CGRect)?
    }

    /// A window we snapped: its size before and the frame we gave it, Cocoa
    /// coordinates.
    private struct Record {
        let element: AXUIElement
        let originalSize: CGSize
        let snappedFrame: CGRect
    }

    private static let readInterval: TimeInterval = 0.05
    private static let maxRecords = 32
    private static let maxLookups = 3
    private static let giveUpTime: TimeInterval = 1
    private static let giveUpDistance: CGFloat = 40

    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "windowSnap")
    private let settings: AppSettings
    private let preview = SnapPreviewWindow()
    private var monitors: [Any] = []
    private var gesture: Gesture?
    private var records: [Record] = []
    private var previewFrame: CGRect?
    private var verifyTask: Task<Void, Never>?
    private var escapePoll: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isRunning: Bool { !monitors.isEmpty }

    /// Installs or removes the monitors to match the setting and the
    /// Accessibility permission.
    func sync() {
        let wanted = settings.windowSnapByDragging && AccessibilityPermission.isTrusted
        if wanted && !isRunning {
            install()
        } else if !wanted && isRunning {
            stop()
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        records = []
        verifyTask?.cancel()
        verifyTask = nil
        cancel()
    }

    private func install() {
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(monitor)
        }
        // Esc cancels the gesture.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            MainActor.assumeIsolated {
                if code == 53 {
                    self?.log.debug("esc keyDown received")
                    self?.cancel()
                }
            }
        }) {
            monitors.append(monitor)
        }
    }

    // MARK: - Gesture

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            hidePreview()
            verifyTask?.cancel()
            verifyTask = nil
            gesture = Gesture(grab: NSEvent.mouseLocation)
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            released()
        default:
            break
        }
    }

    private func cancel() {
        gesture = nil
        hidePreview()
    }

    private func hidePreview() {
        escapePoll?.cancel()
        escapePoll = nil
        guard previewFrame != nil else { return }
        previewFrame = nil
        preview.hide()
    }

    private func primaryHeight() -> CGFloat? {
        let screens = NSScreen.screens
        return (screens.first(where: { $0.frame.origin == .zero }) ?? screens.first)?.frame.height
    }

    /// Esc (kVK_Escape) held now. The window server drives a title-bar drag,
    /// so the key monitor may never see the key; the key state always works.
    private var isEscapeDown: Bool {
        CGEventSource.keyState(.combinedSessionState, key: 0x35)
    }

    /// Esc while the mouse is still: polls while a preview is shown.
    private func startEscapePoll() {
        guard escapePoll == nil else { return }
        escapePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self, var g = gesture, !g.abandoned, previewFrame != nil
                else { return }
                if isEscapeDown {
                    abandon(&g, "escape", window: g.window)
                    gesture = g
                    return
                }
            }
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func dragged() {
        guard var g = gesture, !g.abandoned else { return }
        defer { gesture = g }
        if isEscapeDown {
            abandon(&g, "escape", window: g.window)
            return
        }
        guard let primaryHeight = primaryHeight() else {
            abandon(&g, "no screen")
            return
        }
        let cursor = NSEvent.mouseLocation

        if g.window == nil {
            // First attempt at the mouse-down point, then at the pointer.
            lookUp(&g, at: g.lookups == 0 ? g.grab : cursor, cursor: cursor, primaryHeight: primaryHeight)
            return
        }
        guard let window = g.window, let start = g.startFrame else { return }

        if !g.isMove {
            guard Date().timeIntervalSince(g.lastRead) >= Self.readInterval else { return }
            g.lastRead = Date()
            guard let axFrame = window.frame else {
                abandon(&g, "frame unreadable", window: window)
                return
            }
            let current = WindowLayout.axToCocoa(axFrame, primaryHeight: primaryHeight)
            switch DragMotion.classify(start: start, current: current) {
            case .resized:
                abandon(&g, "resized", window: window)
                return
            case .unchanged:
                // The hit may have missed the window that follows the pointer.
                if g.lookups < Self.maxLookups, distance(cursor, g.grab) > 4 {
                    lookUp(&g, at: cursor, cursor: cursor, primaryHeight: primaryHeight)
                } else if g.lookups >= Self.maxLookups,
                          distance(cursor, g.grab) > Self.giveUpDistance
                            || Date().timeIntervalSince(g.startedAt) > Self.giveUpTime {
                    abandon(&g, "window not moving", window: window)
                }
                return
            case .moved:
                beginMove(&g, window: window, start: start)
            }
        }

        if g.pendingRestore != nil { restoreSize(&g, window: window, primaryHeight: primaryHeight) }

        let snapScreens = NSScreen.screens.map { SnapScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let hit = SnapArea.detect(cursor: cursor, screens: snapScreens),
              let frame = WindowLayout.frame(
                for: hit.area.action, windowFrame: start, visibleFrame: snapScreens[hit.screenIndex].visibleFrame)
        else {
            g.target = nil
            hidePreview()
            return
        }
        g.target = (hit.area, frame)
        if previewFrame != frame {
            previewFrame = frame
            preview.show(frame: frame)
            startEscapePoll()
        }
    }

    /// Finds the window at `point` and starts tracking it (replacing the
    /// one tracked so far, which didn't move).
    private func lookUp(_ g: inout Gesture, at point: CGPoint, cursor: CGPoint, primaryHeight: CGFloat) {
        g.lookups += 1
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        guard case .success(let window) = AXWindow.window(atAX: axPoint) else {
            if g.lookups >= Self.maxLookups { abandon(&g, "no window under pointer") }
            return
        }
        if let tracked = g.window, CFEqual(tracked.element, window.element) { return }
        guard !window.isFullScreen else { abandon(&g, "full screen", window: window); return }
        guard window.isMovable, window.isResizable else { abandon(&g, "not movable or resizable", window: window); return }
        guard let frame = window.frame else { abandon(&g, "frame unreadable", window: window); return }
        g.window = window
        g.startFrame = WindowLayout.axToCocoa(frame, primaryHeight: primaryHeight)
        g.startCursor = cursor
        g.lastRead = Date()
    }

    /// The window started moving: decide whether it is one we snapped.
    private func beginMove(_ g: inout Gesture, window: AXWindow, start: CGRect) {
        g.isMove = true
        g.originalSize = start.size
        guard let index = records.firstIndex(where: { CFEqual($0.element, window.element) }) else { return }
        let record = records[index]
        let slack = distance(g.startCursor, g.grab)
        if SnapRestore.matches(snappedFrame: record.snappedFrame, observed: start, slack: slack) {
            g.pendingRestore = record
            g.originalSize = record.originalSize
        } else {
            records.remove(at: index)
        }
    }

    /// Gives a window we snapped its earlier size back. The window server
    /// is driving the drag, so the size is verified and tried once more on
    /// the next drag event.
    private func restoreSize(_ g: inout Gesture, window: AXWindow, primaryHeight: CGFloat) {
        guard let record = g.pendingRestore else { return }
        func finish() {
            g.pendingRestore = nil
            records.removeAll { CFEqual($0.element, record.element) }
        }
        if g.restoreTries > 0 {
            // Did the previous attempt hold?
            if let size = window.size, abs(size.width - record.originalSize.width) <= 2,
               abs(size.height - record.originalSize.height) <= 2 {
                finish()
                return
            }
        }
        guard g.restoreTries < 2 else {
            log.debug("restore gave up pid \(self.pid(of: window))")
            finish()
            return
        }
        g.restoreTries += 1
        guard let restored = SnapRestore.frame(
            originalSize: record.originalSize, snappedFrame: record.snappedFrame,
            grab: g.grab, cursor: NSEvent.mouseLocation)
        else {
            finish()
            return
        }
        let ax = WindowLayout.cocoaToAX(restored, primaryHeight: primaryHeight)
        window.setSize(ax.size)
        window.setPosition(ax.origin)
    }

    private func released() {
        guard let g = gesture else { return }
        gesture = nil
        hidePreview()
        guard g.isMove, !g.abandoned, let window = g.window, let target = g.target,
              let primaryHeight = primaryHeight() else { return }
        let ax = WindowLayout.cocoaToAX(target.frame, primaryHeight: primaryHeight)
        guard window.setFrame(ax) else {
            log.debug("snap failed pid \(self.pid(of: window))")
            return
        }
        log.debug("snapped pid \(self.pid(of: window)) to \(String(describing: target.area), privacy: .public)")
        records.removeAll { CFEqual($0.element, window.element) }
        if let size = g.originalSize {
            records.append(Record(element: window.element, originalSize: size, snappedFrame: target.frame))
        }
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        // The window server may still apply the end of the drag: check once.
        verifyTask?.cancel()
        verifyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, self != nil, let frame = window.frame else { return }
            let off = abs(frame.minX - ax.minX) > 2 || abs(frame.minY - ax.minY) > 2
                || abs(frame.width - ax.width) > 2 || abs(frame.height - ax.height) > 2
            if off { window.setFrame(ax) }
        }
    }

    private func abandon(_ g: inout Gesture, _ reason: String, window: AXWindow? = nil) {
        g.abandoned = true
        g.target = nil
        hidePreview()
        if let window {
            log.debug("abandon: \(reason, privacy: .public) pid \(self.pid(of: window))")
        } else {
            log.debug("abandon: \(reason, privacy: .public)")
        }
    }

    private func pid(of window: AXWindow) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(window.element, &pid)
        return pid
    }
}
