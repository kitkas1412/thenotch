//
//  IslandPanel.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import AppKit

/// Borderless, transparent panel that floats above the menu bar on every
/// Space. It never becomes key/main (so clicking it doesn't steal focus
/// from the frontmost app), except while the controller sets
/// `acceptsKeyboard` for a module that takes typing; it still never
/// activates the app.
@MainActor
final class IslandPanel: NSPanel {
    /// Set by the controller while the shown module takes the keyboard.
    var acceptsKeyboard = false
    /// Offered key presses before the first responder sees them; returns
    /// whether it handled the event.
    var keyHandler: ((NSEvent) -> Bool)?
    /// The panel lost key status.
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .mainMenu + 3  // try .screenSaver if the menu bar covers it
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { acceptsKeyboard }
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

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
