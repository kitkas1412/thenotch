//
//  SystemSampler.swift
//  thenotch
//

import AppKit
import Observation

/// Publishes `snapshot`, read off the main thread every `interval` (1 s
/// while the popover is open). Nothing runs while nobody can see the menu
/// bar: display asleep, screen locked or another user's session in front.
@MainActor
@Observable
final class SystemSampler {
    private(set) var snapshot = SystemSnapshot()

    /// Seconds between readings while the popover is closed.
    var interval: TimeInterval = SystemMonitorInterval.two.seconds {
        didSet { if interval != oldValue { restart() } }
    }

    /// The popover is open: read every second.
    var isPopoverOpen = false {
        didSet { if isPopoverOpen != oldValue { restart(readNow: isPopoverOpen) } }
    }

    @ObservationIgnored private let reader = SystemReader()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isPrimed = false
    @ObservationIgnored private var ambient = AmbientConditions()
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeConditions()
        restart()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        ambient = AmbientConditions()
        cancel()
    }

    private func cancel() {
        task?.cancel()
        task = nil
    }

    /// (Re)starts the loop, or leaves it stopped while paused.
    private func restart(readNow: Bool = false) {
        cancel()
        guard isStarted else { return }
        guard ambient.isVisible else {
            isPrimed = false
            return
        }
        task = Task { [weak self] in
            await self?.run(readNow: readNow)
        }
    }

    private func run(readNow: Bool) async {
        var delay = currentDelay
        if isPrimed && readNow {
            // The popover just opened: show fresh values at once.
            let next = await reader.read()
            guard !Task.isCancelled else { return }
            publish(next)
        }
        if !isPrimed {
            await reader.reset()
            let first = await reader.read()
            guard !Task.isCancelled else { return }
            publish(first)
            isPrimed = true
            delay = 0.5
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let next = await reader.read()
            guard !Task.isCancelled else { return }
            publish(next)
            delay = currentDelay
        }
    }

    private var currentDelay: TimeInterval {
        isPopoverOpen ? 1 : interval
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
