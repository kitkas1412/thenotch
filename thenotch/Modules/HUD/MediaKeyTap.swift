//
//  MediaKeyTap.swift
//  thenotch
//

import AppKit
import CoreGraphics

/// Intercepts the volume and brightness keys with a Quartz event tap, so
/// a handler can act on them instead of macOS (and its overlay). Needs
/// Accessibility permission; `start()` fails without it.
@MainActor
final class MediaKeyTap {
    /// Returns whether the key was handled: handled keys don't reach macOS.
    var onPress: ((MediaKey.Press, CGEventFlags) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// `NX_SYSDEFINED`, the event type of special keys; not in `CGEventType`.
    private static let systemDefined: UInt32 = 14

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << Self.systemDefined)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                // The tap's source is on the main run loop.
                return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a slow tap off; turn it back on.
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return passThrough
        case .keyDown, .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard let key = MediaKey.brightnessKey(keyCode: keyCode) else { return passThrough }
            let press = MediaKey.Press(
                key: key,
                isDown: type == .keyDown,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
            return onPress?(press, event.flags) == true ? nil : passThrough
        default:
            guard type.rawValue == Self.systemDefined,
                  let nsEvent = NSEvent(cgEvent: event),
                  let press = MediaKey.press(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1)
            else { return passThrough }
            return onPress?(press, event.flags) == true ? nil : passThrough
        }
    }
}
