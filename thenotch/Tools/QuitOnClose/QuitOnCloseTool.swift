//
//  QuitOnCloseTool.swift
//  thenotch
//

import AppKit
import os

/// Quits an app a moment after its last real window closes. Needs
/// Accessibility; watches only while it is granted.
@MainActor
final class QuitOnCloseTool: Tool {
    let id = ToolKind.quitOnClose.id
    private let settings: AppSettings
    private let log = Logger(subsystem: AppIdentity.logSubsystem, category: "quitOnClose")
    private var watchers: [pid_t: AppWindowWatcher] = [:]
    private var checks: [pid_t: Task<Void, Never>] = [:]
    private var attachTasks: [pid_t: Task<Void, Never>] = [:]
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var recheckTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    /// Failed attaches by pid; an app is tried at most `maxAttempts` times.
    private var failures: [pid_t: Int] = [:]
    private static let maxAttempts = 2

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: AccessibilityPermission.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissionChanged() }
        }))
        let local = NotificationCenter.default
        observers.append((local, local.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { self?.appLaunched(app) } }
        }))
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { self?.forget(app.processIdentifier) } }
        }))
        sync()
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
        recheckTask?.cancel()
        recheckTask = nil
        syncTask?.cancel()
        syncTask = nil
        detachAll()
    }

    // MARK: - Watching

    private var isTrusted: Bool { AccessibilityPermission.isTrusted }

    private func permissionChanged() {
        failures = [:]
        sync()
        // The notification can arrive before `isTrusted` reflects it.
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.sync()
        }
    }

    /// Attaches the running apps one at a time, so a hung app can't hold the
    /// main thread for the whole list.
    private func sync() {
        syncTask?.cancel()
        syncTask = nil
        guard isTrusted else {
            detachAll()
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            isWatchable($0) && watchers[$0.processIdentifier] == nil
                && attachTasks[$0.processIdentifier] == nil
                && failures[$0.processIdentifier, default: 0] < Self.maxAttempts
        }
        guard !apps.isEmpty else { return }
        syncTask = Task { [weak self] in
            for app in apps {
                guard !Task.isCancelled, let self, isTrusted else { return }
                if !app.isTerminated, watchers[app.processIdentifier] == nil {
                    attach(app)
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func isWatchable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func appLaunched(_ app: NSRunningApplication) {
        guard isTrusted, isWatchable(app) else { return }
        let pid = app.processIdentifier
        failures[pid] = nil
        // A new app takes a moment to answer Accessibility; one retry.
        attachTasks[pid]?.cancel()
        attachTasks[pid] = Task { [weak self] in
            for delay in [1, 2] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, isTrusted, !app.isTerminated else { return }
                if attach(app) { break }
            }
            self?.attachTasks[pid] = nil
        }
    }

    @discardableResult
    private func attach(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard watchers[pid] == nil else { return true }
        let watcher = AppWindowWatcher(pid: pid)
        watcher.onWindowCreated = { [weak self] in self?.cancelCheck(pid) }
        watcher.onRealWindowDestroyed = { [weak self] in self?.scheduleCheck(pid) }
        guard watcher.attach() else {
            watcher.detach()
            failures[pid, default: 0] += 1
            return false
        }
        watchers[pid] = watcher
        return true
    }

    private func forget(_ pid: pid_t) {
        cancelCheck(pid)
        failures[pid] = nil
        attachTasks[pid]?.cancel()
        attachTasks[pid] = nil
        watchers[pid]?.detach()
        watchers[pid] = nil
    }

    private func detachAll() {
        for task in checks.values { task.cancel() }
        checks = [:]
        for task in attachTasks.values { task.cancel() }
        attachTasks = [:]
        for watcher in watchers.values { watcher.detach() }
        watchers = [:]
    }

    // MARK: - Checking

    private func cancelCheck(_ pid: pid_t) {
        checks[pid]?.cancel()
        checks[pid] = nil
    }

    private func scheduleCheck(_ pid: pid_t) {
        checks[pid]?.cancel()
        let delay = settings.quitOnCloseDelay
        checks[pid] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.checks[pid] = nil
            self?.check(pid)
        }
    }

    private func check(_ pid: pid_t) {
        guard isTrusted, let app = NSRunningApplication(processIdentifier: pid) else { return }
        let input = QuitDecision.Input(
            axSubroles: WindowInventory.axSubroles(pid: pid),
            cgWindows: WindowInventory.cgWindows(pid: pid),
            pid: pid,
            isRunning: !app.isTerminated,
            finishedLaunching: app.isFinishedLaunching,
            isHidden: app.isHidden,
            isRegular: app.activationPolicy == .regular,
            isFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            bundleID: app.bundleIdentifier,
            mode: settings.quitOnCloseMode,
            listedApps: settings.quitOnCloseApps
        )
        switch QuitDecision.decide(input) {
        case .quit:
            log.info("Quitting \(app.bundleIdentifier ?? "?", privacy: .public)")
            app.terminate()
        case .skip(let reason):
            log.debug("Not quitting \(app.bundleIdentifier ?? "?", privacy: .public): \(String(describing: reason), privacy: .public)")
        }
    }
}
