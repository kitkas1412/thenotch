//
//  MediaKeyTap.swift
//  thenotch
//

import AppKit
import CoreGraphics

/// Intercepts the volume and brightness keys with a Quartz event tap, so
/// a handler can act on them instead of macOS (and its overlay). Needs
/// Accessibility permission; `start()` fails without it.
///
/// The tap also sees every other key press (for the brightness key codes),
/// and macOS waits for it before delivering each one. It runs on its own
/// thread, so typing never waits on the main thread; `onPress` is called
/// there too.
final class MediaKeyTap: @unchecked Sendable {
    /// Called on the tap's thread. Returns whether the key was handled:
    /// handled keys don't reach macOS.
    private let onPress: (MediaKey.Press, CGEventFlags) -> Bool

    /// Guards `tap` and `runLoop`, shared by the caller's thread and the
    /// tap's.
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    /// `NX_SYSDEFINED`, the event type of special keys; not in `CGEventType`.
    private static let systemDefined: UInt32 = 14

    init(onPress: @escaping (MediaKey.Press, CGEventFlags) -> Bool) {
        self.onPress = onPress
    }

    deinit {
        stop()
    }

    var isRunning: Bool {
        lock.withLock { tap != nil }
    }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
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
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let thread = Thread { [weak self] in
            // Not holding `self` while running, so it can still go away.
            guard self?.attach(tap, to: CFRunLoopGetCurrent()) == true else { return }
            // Returns once stopped.
            CFRunLoopRun()
        }
        thread.name = "MediaKeyTap"
        // Key presses wait on it: run it ahead of ordinary work.
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// On the tap's thread: listens there, unless stopped meanwhile.
    private func attach(_ tap: CFMachPort, to runLoop: CFRunLoop) -> Bool {
        lock.withLock {
            guard self.tap === tap else { return false }
            self.runLoop = runLoop
            CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            return true
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        // Removes its source from the run loop, so the thread can end.
        CFMachPortInvalidate(tap)
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        self.tap = nil
        runLoop = nil
    }

    /// On the tap's thread.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a slow tap off; turn it back on.
            if let tap = lock.withLock({ tap }) {
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
            return onPress(press, event.flags) ? nil : passThrough
        default:
            guard type.rawValue == Self.systemDefined,
                  let nsEvent = NSEvent(cgEvent: event),
                  let press = MediaKey.press(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1)
            else { return passThrough }
            return onPress(press, event.flags) ? nil : passThrough
        }
    }
}
