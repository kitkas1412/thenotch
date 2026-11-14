//
//  WindowManagerTool.swift
//  thenotch
//

import AppKit

/// Moves and resizes the focused window with global shortcuts.
@MainActor
final class WindowManagerTool: Tool {
    let id = ToolKind.windowManagement.id
    private let settings: AppSettings
    private let hotKeys: HotKeyCenter
    private var observation: ShortcutObservation?
    private var permissionObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var recheckTask: Task<Void, Never>?

    init(settings: AppSettings, hotKeys: HotKeyCenter) {
        self.settings = settings
        self.hotKeys = hotKeys
    }

    func start() {
        syncRegistrations()
        observation = settings.observeShortcuts { [weak self] actionID in
            guard let self, isTrusted,
                  let action = WindowAction.allCases.first(where: {
                      ShortcutAction.windowActionID($0) == actionID
                  }) else { return }
            register(action)
        }
        // The hotkeys exist only while Accessibility is granted, so they
        // don't swallow keys just to beep.
        let distributed = DistributedNotificationCenter.default()
        permissionObservers.append((distributed, distributed.addObserver(
            forName: AccessibilityPermission.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissionChanged() }
        }))
        let local = NotificationCenter.default
        permissionObservers.append((local, local.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncRegistrations() }
        }))
    }

    func stop() {
        observation?.cancel()
        observation = nil
        for observer in permissionObservers {
            observer.center.removeObserver(observer.token)
        }
        permissionObservers = []
        recheckTask?.cancel()
        recheckTask = nil
        unregisterAll()
    }

    private var isTrusted: Bool { AccessibilityPermission.isTrusted }

    private func permissionChanged() {
        syncRegistrations()
        // The notification can arrive before `isTrusted` reflects it.
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.syncRegistrations()
        }
    }

    private func syncRegistrations() {
        if isTrusted {
            for action in WindowAction.allCases { register(action) }
        } else {
            unregisterAll()
        }
    }

    private func unregisterAll() {
        for action in WindowAction.allCases {
            hotKeys.unregister(id: ShortcutAction.windowActionID(action))
        }
    }

    private func register(_ action: WindowAction) {
        let actionID = ShortcutAction.windowActionID(action)
        guard let shortcut = settings.shortcut(for: actionID) else {
            hotKeys.unregister(id: actionID)
            return
        }
        hotKeys.register(id: actionID, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
    }

    private func perform(_ action: WindowAction) {
        guard case .success(let window) = AXWindow.focused() else {
            NSSound.beep()
            return
        }
        guard !window.isFullScreen, let axFrame = window.frame else { return }
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else { return }
        let primaryHeight = primary.frame.height
        let windowFrame = WindowLayout.axToCocoa(axFrame, primaryHeight: primaryHeight)
        let frames = screens.map(\.frame)
        guard let current = WindowLayout.screenIndex(containing: windowFrame, screens: frames) else { return }

        let target: CGRect
        if action.changesDisplay {
            let index = WindowLayout.targetScreenIndex(
                current: current, count: screens.count, forward: action == .nextDisplay)
            guard index != current else { return }
            target = WindowLayout.movedToDisplay(
                windowFrame: windowFrame,
                from: screens[current].visibleFrame,
                to: screens[index].visibleFrame)
        } else if let frame = WindowLayout.frame(
            for: action, windowFrame: windowFrame, visibleFrame: screens[current].visibleFrame) {
            target = frame
        } else {
            return
        }
        if !window.setFrame(WindowLayout.cocoaToAX(target, primaryHeight: primaryHeight)) {
            NSSound.beep()
        }
    }
}
