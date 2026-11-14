//
//  WindowInventory.swift
//  thenotch
//

import AppKit
import ApplicationServices
import os

/// What counts as a window of an app: the classification is pure, the
/// readers are thin wrappers over Accessibility and the window list.
enum WindowInventory {
    /// A window of the window list, reduced to what the decision needs.
    struct CGWindow: Equatable {
        var pid: pid_t
        var layer: Int
        var alpha: Double
        var width: Double
        var height: Double
        /// Spaces the window is on; 0 for a window AppKit keeps ordered out.
        /// `nil` when unknown, which counts as visible.
        var number: Int = 0
        var spaceCount: Int?
        /// `false` for a window AppKit keeps ordered out (closed, but kept
        /// for reuse). `nil` when unknown, which counts as visible.
        var isOrderedIn: Bool?
    }

    /// Smallest side, in points, of a window that keeps an app open.
    static let minimumSide = 40.0

    private static let nonWindowSubroles: Set<String> = [
        kAXFloatingWindowSubrole as String,
        kAXSystemFloatingWindowSubrole as String,
    ]

    /// A standard window, a dialog, or anything unknown (missing subrole
    /// included); only floating panels are not real windows.
    static func isRealWindow(subrole: String?) -> Bool {
        guard let subrole else { return true }
        return !nonWindowSubroles.contains(subrole)
    }

    /// Whether the list has a visible, normal-level window of the app. A
    /// window with a missing field counts, to be safe.
    static func hasVisibleWindow(_ windows: [CGWindow], pid: pid_t) -> Bool {
        windows.contains {
            $0.pid == pid && $0.isCandidate && $0.spaceCount != 0 && $0.isOrderedIn != false
        }
    }

    /// Reads owner, number, layer, alpha and size from
    /// `CGWindowListCopyWindowInfo` dictionaries (never names). Entries
    /// without an owner are dropped. `spaces` (by window number) is asked
    /// and `orderedIn` only for the windows of `pid` (all when `nil`) that could keep the
    /// app open.
    static func windows(
        from info: [[String: Any]],
        pid targetPid: pid_t? = nil,
        spaces: (Int) -> Int? = { _ in nil },
        orderedIn: (Int) -> Bool? = { _ in nil }
    ) -> [CGWindow] {
        info.compactMap { entry in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            let bounds = entry[kCGWindowBounds as String] as? [String: Any]
            var window = CGWindow(
                pid: pid,
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                width: (bounds?["Width"] as? NSNumber)?.doubleValue ?? .infinity,
                height: (bounds?["Height"] as? NSNumber)?.doubleValue ?? .infinity,
                number: (entry[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            )
            if window.isCandidate, targetPid == nil || targetPid == pid, entry[kCGWindowNumber as String] != nil {
                window.spaceCount = spaces(window.number)
                window.isOrderedIn = orderedIn(window.number)
            }
            return window
        }
    }

    // MARK: - Readers

    /// Subroles of the app's windows; `nil` when the list can't be read.
    @MainActor
    static func axSubroles(pid: pid_t) -> [String?]? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, AXWindow.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID(),
              let elements = value as? [AXUIElement]
        else { return nil }
        return elements.map(subrole(of:))
    }

    @MainActor
    static func subrole(of element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, AXWindow.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// The windows the system lists, on this Space or not, with the Spaces
    /// of the app's candidate windows. `nil` on any failure, so an unknown
    /// never reads as "no window".
    static func cgWindows(pid: pid_t) -> [CGWindow]? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        guard let spaces = SpacesLookup.shared else {
            logOnce("Spaces lookup unavailable")
            return nil
        }
        var failed = false
        let windows = windows(from: list, pid: pid, spaces: { number in
            guard let count = spaces.count(forWindow: number) else {
                failed = true
                return nil
            }
            return count
        }, orderedIn: { spaces.isOrderedIn(window: $0) })
        if failed {
            logOnce("Spaces lookup failed")
            return nil
        }
        return windows
    }

    private nonisolated(unsafe) static var logged = false

    private static func logOnce(_ reason: String) {
        guard !logged else { return }
        logged = true
        Logger(subsystem: AppIdentity.logSubsystem, category: "quitOnClose")
            .error("\(reason, privacy: .public): Quit on Close skips apps")
    }

    /// AppKit keeps closed windows ordered out, and the window list still
    /// has them; only a window's Spaces and whether it is ordered in tell
    /// them from a window on another Space. That needs private SkyLight (or CGS) functions, looked
    /// up by name so a missing one fails safe.
    private struct SpacesLookup {
        typealias MainConnection = @convention(c) () -> Int32
        typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        typealias IsOrderedIn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt8>) -> Int32

        static let shared: SpacesLookup? = {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
            else { return nil }
            for (connection, copy, ordered) in [
                ("SLSMainConnectionID", "SLSCopySpacesForWindows", "SLSWindowIsOrderedIn"),
                ("CGSMainConnectionID", "CGSCopySpacesForWindows", "CGSWindowIsOrderedIn"),
            ] {
                if let c = dlsym(handle, connection), let f = dlsym(handle, copy), let o = dlsym(handle, ordered) {
                    return SpacesLookup(
                        connection: unsafeBitCast(c, to: MainConnection.self),
                        copySpaces: unsafeBitCast(f, to: CopySpaces.self),
                        windowIsOrderedIn: unsafeBitCast(o, to: IsOrderedIn.self))
                }
            }
            return nil
        }()

        let connection: MainConnection
        let copySpaces: CopySpaces
        let windowIsOrderedIn: IsOrderedIn

        /// `nil` when the call fails.
        func isOrderedIn(window number: Int) -> Bool? {
            var flag: UInt8 = 0
            guard windowIsOrderedIn(connection(), UInt32(truncatingIfNeeded: number), &flag) == 0 else { return nil }
            return flag != 0
        }

        /// One window per call: several ids return the union.
        func count(forWindow number: Int) -> Int? {
            // 7: every Space.
            guard let result = copySpaces(connection(), 7, [NSNumber(value: number)] as CFArray)?.takeRetainedValue()
            else { return nil }
            return CFArrayGetCount(result)
        }
    }
}

extension WindowInventory.CGWindow {
    /// Normal level, not transparent, and big enough to be a window.
    var isCandidate: Bool {
        layer == 0 && alpha > 0
            && width >= WindowInventory.minimumSide && height >= WindowInventory.minimumSide
    }
}
