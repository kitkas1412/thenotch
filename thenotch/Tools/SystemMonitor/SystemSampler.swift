//
//  SystemSampler.swift
//  thenotch
//

import AppKit
import Observation

/// Whether the sampler should be reading: the tool is on, the menu panel is
/// open and somebody can see the screen.
enum SystemSampling {
    static func shouldSample(isEnabled: Bool, isPanelVisible: Bool, ambientVisible: Bool) -> Bool {
        isEnabled && isPanelVisible && ambientVisible
    }
}

/// Publishes `snapshot`, read off the main thread every second, only while
/// the System Monitor tool is on and the menu panel is open (and the display
/// is awake, the screen unlocked and the session active). Otherwise nothing
/// runs and no observer is registered beyond the tool's own lifetime.
@MainActor
@Observable
final class SystemSampler {
    private(set) var snapshot = SystemSnapshot()

    /// Set by `SystemMonitorTool`: the tool is on.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                ambient = Self.currentConditions()
                observeConditions()
            } else {
                removeObservers()
            }
            restart()
        }
    }

    /// Set by `PanelWindowTracker` in `App/MenuPanel.swift`.
    var isPanelVisible = false {
        didSet { if isPanelVisible != oldValue { restart() } }
    }

    static let interval: TimeInterval = 1

    @ObservationIgnored private let reader = SystemReader()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var ambient = AmbientConditions()
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// The conditions right now, so enabling while the screen is locked or
    /// asleep doesn't count as visible until the next notification. The lock
    /// state comes from the session dictionary (undocumented key, but stable
    /// for years); absent keys read as visible.
    private static func currentConditions() -> AmbientConditions {
        var conditions = AmbientConditions()
        conditions.isDisplayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            conditions.isScreenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
            conditions.isSessionInactive = !(session["kCGSSessionOnConsoleKey"] as? Bool ?? true)
        }
        return conditions
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        ambient = AmbientConditions()
    }

    private func cancel() {
        task?.cancel()
        task = nil
    }

    /// (Re)starts the loop, or leaves it stopped while it shouldn't sample.
    private func restart() {
        cancel()
        guard SystemSampling.shouldSample(
            isEnabled: isEnabled, isPanelVisible: isPanelVisible, ambientVisible: ambient.isVisible
        ) else {
            // Back to the "no reading yet" placeholder, so the next open
            // never shows values from an earlier one.
            publish(SystemSnapshot())
            return
        }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        // Prime: the first reading has no CPU/network delta, so it isn't
        // published; the panel keeps its placeholder until the second one.
        await reader.reset()
        _ = await reader.read()
        var delay = 0.5
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let next = await reader.read()
            guard !Task.isCancelled else { return }
            publish(next)
            delay = Self.interval
        }
    }

    private func publish(_ new: SystemSnapshot) {
        if new != snapshot { snapshot = new }
    }

    // MARK: Pause conditions

    private func observeConditions() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isDisplayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isDisplayAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }
        // Posted by loginwindow; there's no public API for the lock state.
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
                let wasVisible = self.ambient.isVisible
                self.ambient = conditions
                if conditions.isVisible != wasVisible { self.restart() }
            }
        }
        observers.append((center, token))
    }
}
