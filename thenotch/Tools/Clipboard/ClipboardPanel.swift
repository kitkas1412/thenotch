//
//  ClipboardPanel.swift
//  thenotch
//

import AppKit
import SwiftUI

/// The history panel's window: borderless, never activates the app (the
/// previous app stays in front, so ⌘V lands there), but can be key to take
/// typing. Keys are offered to `keyHandler` before the search field sees
/// them (arrows, return and ⌘-digits would otherwise move the text cursor),
/// except while an input method is composing in the search field.
final class ClipboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    /// Closes the panel through its controller (Esc the handler didn't take).
    var cancelHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposing, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// An input method has marked text (e.g. Japanese, Chinese): its keys
    /// (Return, arrows, Esc) belong to it.
    private var isComposing: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    override func cancelOperation(_ sender: Any?) {
        if let cancelHandler {
            cancelHandler()
        } else {
            orderOut(nil)
        }
    }
}

/// Shows the history panel under the notch and the small "Copied" toast.
@MainActor
final class ClipboardPanelController: ClipboardPanelPresenting {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 460
    private static let minHeight: CGFloat = 170

    private unowned let tool: ClipboardTool
    private var panel: ClipboardPanel?
    private var model: ClipboardHistoryModel?
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private let toast = ClipboardToastController()

    init(tool: ClipboardTool) {
        self.tool = tool
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: ClipboardPanelPresenting

    func showClipboardHistory() {
        if isVisible {
            close()
            return
        }
        toast.hide()
        let model = ClipboardHistoryModel(tool: tool)
        model.onChoose = { [weak self] item, plain in self?.choose(item, asPlainText: plain) }
        model.onClose = { [weak self] in self?.close() }
        self.model = model

        let height = Self.height(forItemCount: tool.store.items.count)
        let size = CGSize(width: Self.width, height: height)
        let panel = makePanel(size: size, model: model)
        self.panel = panel
        let frame = Self.frame(size: size)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: 14), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
        observe(panel)
        NSAccessibility.post(element: panel, notification: .layoutChanged)
    }

    /// Closes the panel and hides the toast.
    func close() {
        toast.hide()
        guard let panel else { return }
        removeObservers()
        self.panel = nil
        model = nil
        panel.keyHandler = nil
        panel.cancelHandler = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: Choosing

    private func choose(_ item: ClipboardItem, asPlainText: Bool) {
        close()
        let tool = tool
        Task { [weak self] in
            switch await tool.paste(item, asPlainText: asPlainText) {
            case .pasted: break
            case .copied: self?.toast.show("Copied — press ⌘V", symbol: "doc.on.clipboard")
            case .unavailable: self?.toast.show("Item no longer available", symbol: "exclamationmark.triangle")
            }
        }
    }

    // MARK: Window

    private func makePanel(size: CGSize, model: ClipboardHistoryModel) -> ClipboardPanel {
        let panel = ClipboardPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Kept out of screenshots and screen sharing: it shows copied text.
        panel.sharingType = .none
        panel.title = "Clipboard History"
        panel.setAccessibilityLabel("Clipboard History")
        panel.keyHandler = { [weak model] event in model?.handle(event) ?? false }
        panel.cancelHandler = { [weak self] in self?.close() }
        model.window = panel

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: ClipboardHistoryView(model: model))
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background
        return panel
    }

    private func observe(_ panel: NSPanel) {
        // Leaving the panel (another app, a click elsewhere) closes it.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    static func height(forItemCount count: Int) -> CGFloat {
        min(maxHeight, max(minHeight, 64 + CGFloat(count) * 46 + 10))
    }

    /// Centered on the notch (or under the menu bar's middle on a screen
    /// without one), just below it.
    static func frame(size: CGSize) -> CGRect {
        let screen = anchorScreen()
        let notch = NotchGeometry.notchRect(for: screen)
        let area = screen.visibleFrame
        var x = notch.midX - size.width / 2
        x = min(max(x, area.minX + 8), area.maxX - size.width - 8)
        let top = area.maxY - 6
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    /// The notched display; otherwise the one with the pointer.
    static func anchorScreen() -> NSScreen {
        if let screen = NotchGeometry.targetScreen(), NotchGeometry.hasNotch(topInset: screen.safeAreaInsets.top) {
            return screen
        }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: Toast

/// A short message under the notch. Never takes focus or clicks.
@MainActor
final class ClipboardToastController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, symbol: String) {
        hide()
        let hosting = NSHostingView(rootView: ClipboardToastView(message: message, symbol: symbol))
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.contentView = hosting
        panel.setFrame(ClipboardPanelController.frame(size: size), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        self.panel = panel
        // Status text that VoiceOver should say without moving focus.
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ClipboardToastView: View {
    let message: String
    let symbol: String

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(6)
    }
}
