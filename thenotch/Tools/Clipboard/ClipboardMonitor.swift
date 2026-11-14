//
//  ClipboardMonitor.swift
//  thenotch
//

import AppKit
import Observation

/// Watches the general pasteboard and records what's copied. macOS has no
/// pasteboard notification, so it polls `changeCount` (cheap, and it never
/// shows the "pasted from" prompt), only while running and while someone may
/// be looking at the screen. Contents are never logged.
@MainActor
@Observable
final class ClipboardMonitor {
    /// macOS 15.4+: the user asked for a prompt or denied this app access to
    /// the pasteboard, so nothing is read. Settings can say how to fix it.
    private(set) var privacyBlocked = false

    static let interval: TimeInterval = 0.5

    /// The type our own pasteboard writes carry, so they aren't recorded.
    let ownMarkerType = ClipboardCapture.defaultOwnMarkerType

    /// The change count after our own write (set by `ClipboardPaster`): that
    /// change isn't recorded.
    @ObservationIgnored var lastOwnChangeCount: Int?

    @ObservationIgnored private let store: ClipboardStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var ambient = AmbientConditions()
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(store: ClipboardStore, settings: AppSettings, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // What's on the pasteboard now was copied before; it isn't recorded.
        lastChangeCount = pasteboard.changeCount
        ambient = Self.currentConditions()
        observeConditions()
        updateTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        updateTimer()
    }

    // MARK: Polling

    private func updateTimer() {
        let shouldPoll = isRunning && ambient.isVisible
        if shouldPoll, timer == nil {
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            // Catch what was copied while paused.
            poll()
        } else if !shouldPoll {
            timer?.invalidate()
            timer = nil
        }
    }

    private func poll() {
        updatePrivacy()
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if let own = lastOwnChangeCount, own == count { return }
        guard !privacyBlocked else { return }
        capture()
    }

    private func updatePrivacy() {
        var blocked = false
        if #available(macOS 15.4, *) {
            blocked = pasteboard.accessBehavior == .ask || pasteboard.accessBehavior == .alwaysDeny
        }
        if blocked != privacyBlocked { privacyBlocked = blocked }
    }

    /// Types first (every item's, no data read), then only the data
    /// `ClipboardCapture.read` asks for.
    private func capture() {
        let items = pasteboard.pasteboardItems ?? []
        guard let first = items.first else { return }
        let allTypes = Set(items.flatMap { $0.types.map(\.rawValue) })
        let capture = CaptureSettings(
            ignoredBundleIDs: Set(settings.clipboardIgnoredApps),
            recordsRemote: settings.clipboardRecordsRemote,
            ownMarkerType: ownMarkerType)
        let decision = ClipboardCapture.read(
            firstItemTypes: first.types.map(\.rawValue),
            allTypes: allTypes,
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            settings: capture,
            data: { first.data(forType: NSPasteboard.PasteboardType($0)) },
            fileURLs: {
                items.compactMap { $0.data(forType: NSPasteboard.PasteboardType(ClipboardCapture.Types.fileURL)) }
            })
        if case .capture(let draft) = decision {
            store.add(draft)
        }
    }

    // MARK: Pause conditions

    /// The conditions right now (see `SystemSampler`): the lock state comes
    /// from the session dictionary; absent keys read as visible.
    private static func currentConditions() -> AmbientConditions {
        var conditions = AmbientConditions()
        conditions.isDisplayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            conditions.isScreenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
            conditions.isSessionInactive = !(session["kCGSSessionOnConsoleKey"] as? Bool ?? true)
        }
        return conditions
    }

    private func observeConditions() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isDisplayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isDisplayAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        update: @escaping (inout AmbientConditions) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var conditions = self.ambient
                update(&conditions)
                guard conditions != self.ambient else { return }
                self.ambient = conditions
                self.updateTimer()
            }
        }
        observers.append((center, token))
    }
}
