//
//  AXWindow.swift
//  thenotch
//

import AppKit
import ApplicationServices

/// A window of another app, read and moved through the Accessibility API.
/// Needs Accessibility permission. Frames are in AX coordinates (origin at
/// the top left of the primary display, y down); `WindowLayout` converts.
/// Every call is bounded by `messagingTimeout`, so an unresponsive app can't
/// hold the main thread for long.
@MainActor
struct AXWindow {
    enum Failure: Error, Equatable {
        case notTrusted
        case noApplication
        case noWindow
        case attributeUnavailable
    }

    static let messagingTimeout: Float = 0.25

    let element: AXUIElement

    /// The focused window of the frontmost app (not ours).
    static func focused() -> Result<AXWindow, Failure> {
        guard AccessibilityPermission.isTrusted else { return .failure(.notTrusted) }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return .failure(.noApplication) }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return .failure(.noWindow) }
        // The type ID was checked above.
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return .success(AXWindow(element: element))
    }

    /// The window of another app (not ours) under `point`, in AX coordinates.
    static func window(atAX point: CGPoint) -> Result<AXWindow, Failure> {
        guard AccessibilityPermission.isTrusted else { return .failure(.notTrusted) }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit
        else { return .failure(.noWindow) }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success else { return .failure(.noApplication) }
        guard pid != ProcessInfo.processInfo.processIdentifier else { return .failure(.noApplication) }
        AXUIElementSetMessagingTimeout(hit, messagingTimeout)
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role) == .success,
           (role as? String) == kAXWindowRole {
            return .success(AXWindow(element: hit))
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return .failure(.noWindow) }
        // The type ID was checked above.
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return .success(AXWindow(element: element))
    }

    var position: CGPoint? {
        point(kAXPositionAttribute)
    }

    var size: CGSize? {
        guard let value = axValue(kAXSizeAttribute), AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isFullScreen: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    var isMovable: Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    func setPosition(_ position: CGPoint) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    /// Size, position, size again: the first size may be clamped by the
    /// display the window is on, the last one applies on the new display.
    /// Windows that can't be resized are only moved.
    @discardableResult
    func setFrame(_ frame: CGRect) -> Bool {
        guard isMovable else { return false }
        let resizable = isResizable
        if resizable { setSize(frame.size) }
        let moved = setPosition(frame.origin)
        if resizable { setSize(frame.size) }
        return moved
    }

    private func axValue(_ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // The type ID was checked above.
        return (value as! AXValue)
    }

    private func point(_ attribute: String) -> CGPoint? {
        guard let value = axValue(attribute), AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }
}
