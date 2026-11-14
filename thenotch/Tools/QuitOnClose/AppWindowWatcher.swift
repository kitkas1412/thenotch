//
//  AppWindowWatcher.swift
//  thenotch
//

import AppKit
import ApplicationServices

/// Watches one app's windows through an AXObserver: tells when a real window
/// is created or destroyed. `detach()` must be called before release: the
/// run loop source holds an unretained pointer to the watcher.
@MainActor
final class AppWindowWatcher {
    let pid: pid_t
    var onWindowCreated: (() -> Void)?
    /// A real window was destroyed.
    var onRealWindowDestroyed: (() -> Void)?

    private var observer: AXObserver?
    private var realWindows: Set<AXUIElement> = []

    init(pid: pid_t) {
        self.pid = pid
    }

    /// Whether the app accepted the observer.
    func attach() -> Bool {
        guard observer == nil else { return true }
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<AppWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // Added to the main run loop.
            MainActor.assumeIsolated {
                watcher.changed(element, notification as String)
            }
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, AXWindow.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(created, application, kAXWindowCreatedNotification as CFString, refcon) == .success
        else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        if let windows = Self.windows(of: application) {
            for window in windows { track(window) }
        }
        return true
    }

    func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        realWindows = []
    }

    private func changed(_ element: AXUIElement, _ notification: String) {
        if notification == kAXWindowCreatedNotification as String {
            track(element)
            onWindowCreated?()
        } else if notification == kAXUIElementDestroyedNotification as String {
            if realWindows.remove(element) != nil {
                onRealWindowDestroyed?()
            }
        }
    }

    private func track(_ window: AXUIElement) {
        guard let observer else { return }
        AXUIElementSetMessagingTimeout(window, AXWindow.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // A failed registration only means a missed quit, which is safe.
        AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        if WindowInventory.isRealWindow(subrole: WindowInventory.subrole(of: window)) {
            realWindows.insert(window)
        }
    }

    private static func windows(of application: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID()
        else { return nil }
        return value as? [AXUIElement]
    }
}
