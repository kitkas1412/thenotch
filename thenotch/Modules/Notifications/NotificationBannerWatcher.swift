//
//  NotificationBannerWatcher.swift
//  thenotch
//

import AppKit
import ApplicationServices
import os

/// Watches Notification Center's banners through Accessibility, reports
/// each notification, and moves the banner's window off screen so only the
/// island shows it. The notification itself stays in Notification Center.
///
/// Closing the banner instead doesn't work: macOS keeps it on screen until
/// it has slid in. Moving its window takes effect at once. Each banner gets
/// a new window, so nothing needs restoring when this stops; banners show
/// as usual again.
///
/// Call alerts (`CallAlerts`) are moved off screen too while they ring,
/// and answered through their actions. Their window is put back when this
/// stops, or if it's still there once it no longer holds the call.
@MainActor
final class NotificationBannerWatcher {
    static let notificationCenterID = "com.apple.notificationcenterui"
    /// Far outside every screen.
    private static let offScreen = CGPoint(x: -20_000, y: -20_000)
    /// Accessibility calls wait for Notification Center; don't let a stuck
    /// one hold the main thread.
    private static let messagingTimeout: Float = 0.25
    /// Banner elements kept for `press(_:)`; a banner lasts a few seconds.
    private static let keptElements = 8
    /// How often a ringing call's alert is checked: it ends without a
    /// notification when the caller hangs up or the call is answered
    /// elsewhere.
    private static let ringingCheck: Duration = .milliseconds(500)

    var onNotification: ((BannerNotification) -> Void)?
    var onCall: ((IncomingCall) -> Void)?
    /// The call's id, once its alert is gone.
    var onCallEnded: ((String) -> Void)?

    private var observer: AXObserver?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var accessObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?
    /// Banner elements by notification id, oldest first.
    private var bannerElements: [(id: String, element: AXUIElement)] = []
    private var ringing: Ringing?

    private struct Ringing {
        let call: IncomingCall
        let window: AXUIElement
        let alert: AXUIElement
        let actions: [CallAlerts.Answer: String]
        /// Where macOS put the alert, to put it back.
        let position: CGPoint?
        var checkTask: Task<Void, Never>?
    }

    var isAttached: Bool { observer != nil }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        // Notification Center restarting (it does after a crash or a login
        // change) gets a new process to watch.
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.notificationCenterID else { return }
                MainActor.assumeIsolated {
                    self?.detach()
                    self?.attach()
                }
            }
        }
        // Access granted (or revoked) in System Settings while running. The
        // notification comes before the change applies.
        accessObserver = DistributedNotificationCenter.default().addObserver(
            forName: AccessibilityPermission.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryTask?.cancel()
                self?.retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    self.detach()
                    self.attach()
                }
            }
        }
        attach()
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        if let accessObserver {
            DistributedNotificationCenter.default().removeObserver(accessObserver)
        }
        accessObserver = nil
        retryTask?.cancel()
        retryTask = nil
        detach()
        bannerElements = []
        if let ringing {
            endCall(ringing, restoring: true)
        }
    }

    /// Clicks the banner, as if it were clicked on screen: the app opens on
    /// that notification. Fails once the banner is gone.
    func press(_ id: String) -> Bool {
        guard let element = bannerElements.last(where: { $0.id == id })?.element else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Answers the ringing call as its alert's button would. Fails once
    /// the call has ended.
    func answer(_ id: String, _ answer: CallAlerts.Answer) -> Bool {
        guard let ringing, ringing.call.id == id, let action = ringing.actions[answer] else { return false }
        let result = AXUIElementPerformAction(ringing.alert, action as CFString)
        if result != .success {
            Log.notifications.error("Couldn't answer a call: \(result.rawValue)")
        }
        return result == .success
    }

    // MARK: - Observing

    private func attach() {
        guard observer == nil else { return }
        guard AccessibilityPermission.isTrusted else {
            Log.notifications.notice("No Accessibility access: banners are left to macOS")
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterID).first else {
            Log.notifications.error("Notification Center isn't running")
            return
        }
        let pid = app.processIdentifier
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // Added to the main run loop.
            MainActor.assumeIsolated {
                watcher.changed(element)
            }
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            Log.notifications.error("Couldn't observe Notification Center")
            return
        }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // A banner arrives in a new window; one arriving while another is
        // still up joins its window (a layout change).
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        Log.notifications.debug("Watching Notification Center (\(pid))")
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
    }

    private func changed(_ element: AXUIElement) {
        guard let window = Self.window(of: element) else { return }
        var elements: [String: AXUIElement] = [:]
        let node = Self.snapshot(window, depth: NotificationBanners.snapshotDepth, banners: &elements)
        if let call = CallAlerts.call(in: node) {
            rang(call, in: node, element: elements[call.id], window: window)
            return
        }
        guard NotificationBanners.isBannerWindow(node) else { return }
        let notifications = NotificationBanners.banners(in: node, at: .now)
        hide(window)
        for (id, element) in elements where !bannerElements.contains(where: { $0.id == id }) {
            bannerElements.append((id, element))
        }
        if bannerElements.count > Self.keptElements {
            bannerElements.removeFirst(bannerElements.count - Self.keptElements)
        }
        for notification in notifications {
            onNotification?(notification)
        }
    }

    // MARK: - Calls

    private func rang(_ call: IncomingCall, in tree: AXNode, element: AXUIElement?, window: AXUIElement) {
        guard let element else { return }
        if ringing?.call.id == call.id { return }
        if let ringing {
            endCall(ringing, restoring: true)
        }
        let alertNode = Self.find(call.id, in: tree) ?? tree
        var actions: [CallAlerts.Answer: String] = [:]
        actions[.accept] = CallAlerts.action(.accept, in: alertNode)
        actions[.decline] = CallAlerts.action(.decline, in: alertNode)
        let position = Self.position(of: window)
        hide(window)
        let checkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.ringingCheck)
                guard let self, !Task.isCancelled else { return }
                self.checkRinging()
            }
        }
        ringing = Ringing(call: call, window: window, alert: element, actions: actions, position: position == Self.offScreen ? nil : position, checkTask: checkTask)
        Log.notifications.debug("Call from \(call.appName, privacy: .public)")
        onCall?(call)
    }

    /// Ends the call once its alert is gone (or no longer a call).
    private func checkRinging() {
        guard let ringing else { return }
        var elements: [String: AXUIElement] = [:]
        let node = Self.snapshot(ringing.window, depth: NotificationBanners.snapshotDepth, banners: &elements)
        guard CallAlerts.call(in: node)?.id != ringing.call.id else { return }
        endCall(ringing, restoring: true)
    }

    private func endCall(_ ended: Ringing, restoring: Bool) {
        ended.checkTask?.cancel()
        ringing = nil
        // A window that's gone ignores this.
        if restoring, var position = ended.position, let value = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(ended.window, kAXPositionAttribute as CFString, value)
        }
        onCallEnded?(ended.call.id)
    }

    private static func find(_ identifier: String, in node: AXNode) -> AXNode? {
        if node.identifier == identifier { return node }
        for child in node.children {
            if let found = find(identifier, in: child) { return found }
        }
        return nil
    }

    private func hide(_ window: AXUIElement) {
        if let position = Self.position(of: window), position == Self.offScreen { return }
        var point = Self.offScreen
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success {
            Log.notifications.error("Couldn't move a banner: \(result.rawValue)")
        }
    }

    // MARK: - Accessibility reads

    private static func window(of element: AXUIElement) -> AXUIElement? {
        if string(kAXRoleAttribute, of: element) == kAXWindowRole { return element }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// Copies what `NotificationBanners` and `CallAlerts` read, and collects
    /// the banners' and alerts' elements by id.
    private static func snapshot(_ element: AXUIElement, depth: Int, banners: inout [String: AXUIElement]) -> AXNode {
        var node = AXNode(
            subrole: string(kAXSubroleAttribute, of: element),
            identifier: string(kAXIdentifierAttribute, of: element)
        )
        if node.subrole == NotificationBanners.bannerSubrole || node.subrole == NotificationBanners.alertSubrole {
            node.description = string(kAXDescriptionAttribute, of: element)
            if let id = node.identifier { banners[id] = element }
        }
        if node.subrole == NotificationBanners.alertSubrole {
            var names: CFArray?
            if AXUIElementCopyActionNames(element, &names) == .success {
                node.actions = names as? [String] ?? []
            }
        }
        if node.identifier != nil, node.subrole == nil {
            // The banner's texts (title, subtitle, body).
            node.value = string(kAXValueAttribute, of: element)
        }
        // The panel lists notifications: nothing to read below it.
        guard depth > 0, node.identifier != NotificationBanners.listIdentifier else { return node }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            node.children = list.map { snapshot($0, depth: depth - 1, banners: &banners) }
        }
        return node
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }
}
