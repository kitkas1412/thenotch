//
//  NotificationsModule.swift
//  thenotch
//

import AppKit
import os
import SwiftUI

/// Shows notifications at the notch instead of the macOS banners: a new
/// one opens the island for a few seconds (`LiveActivity.presents`), which
/// lists the latest ones; the sender's icon stays beside the notch if the
/// island can't open. Reads the banners through Accessibility
/// (`NotificationBannerWatcher`); without access, banners are left to
/// macOS. Shows only what the banner shows, so macOS's Show previews and
/// Focus settings apply.
///
/// A call ringing (FaceTime, or an iPhone call through Continuity) opens
/// the island until it stops, with buttons to accept or decline it.
@MainActor
final class NotificationsModule: IslandModule {
    let id = ModuleKind.notifications.id
    /// Above the battery and Bluetooth peeks, below a volume key just
    /// pressed.
    static let priority = 55
    /// How long a new notification keeps the island open: long enough to
    /// read a line, short enough not to stay in the way.
    static let peekDuration: TimeInterval = 2
    /// A ringing call outranks everything else: it can't wait.
    static let callPriority = 80

    private var callActivityID: String { "\(id).call" }
    #if DEBUG
    private static let fakeCallID = "debug.fakeCall"
    #endif

    private let activities: ActivityCenter
    private let watcher = NotificationBannerWatcher()
    private let model = NotificationsModel()
    /// The island opened on the list: what it showed is cleared when it
    /// closes.
    private var wasSeen = false

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        watcher.onNotification = { [weak self] notification in
            self?.received(notification)
        }
        watcher.onCall = { [weak self] call in
            self?.ringing(call)
        }
        watcher.onCallEnded = { [weak self] id in
            self?.callEnded(id)
        }
        watcher.start()
        #if DEBUG
        // Launch with `-debug.fakeCall '<true/>'` to see the call UI
        // without a call; its buttons only end it.
        if UserDefaults.standard.bool(forKey: "debug.fakeCall") {
            ringing(IncomingCall(id: Self.fakeCallID, appName: "FaceTime", caller: "Anna Nguyen", detail: "FaceTime Audio"))
        }
        #endif
    }

    func stop() {
        watcher.stop()
        watcher.onNotification = nil
        watcher.onCall = nil
        watcher.onCallEnded = nil
        model.recent.removeAll()
        model.call = nil
        activities.remove(id: id)
        activities.remove(id: callActivityID)
    }

    func compactLeading() -> AnyView {
        AnyView(NotificationAppIcon(appName: model.call?.appName ?? model.recent.items.first?.appName, size: IslandStyle.Size.compactContent))
    }

    func compactTrailing() -> AnyView {
        if model.call != nil {
            return AnyView(CallRingingSymbol())
        }
        return AnyView(NotificationCountView(model: model))
    }

    func expandedView() -> AnyView {
        if let call = model.call {
            return AnyView(IncomingCallView(call: call) { [weak self] answer in
                self?.answer(call, answer)
            })
        }
        return AnyView(NotificationListView(model: model) { [weak self] notification in
            self?.open(notification)
        })
    }

    /// A ringing call, or notifications not seen in the open island yet.
    var hasExpandedContent: Bool { model.call != nil || !model.recent.items.isEmpty }

    var expandedContentHeight: CGFloat {
        if model.call != nil {
            return IncomingCallView.contentHeight
        }
        return NotificationListView.contentHeight(rows: model.recent.items.count)
    }

    func islandDidExpand() {
        wasSeen = true
    }

    func islandDidCollapse() {
        guard wasSeen else { return }
        wasSeen = false
        model.recent.removeAll()
        activities.remove(id: id)
    }

    private func received(_ notification: BannerNotification) {
        guard model.recent.add(notification) else { return }
        Log.notifications.debug("Banner from \(notification.appName, privacy: .public)")
        activities.publish(LiveActivity(
            id: id,
            moduleID: id,
            priority: Self.priority,
            expiresAt: .now.addingTimeInterval(Self.peekDuration),
            presents: true
        ))
    }

    private func ringing(_ call: IncomingCall) {
        model.call = call
        activities.publish(LiveActivity(
            id: callActivityID,
            moduleID: id,
            priority: Self.callPriority,
            presents: true
        ))
    }

    private func callEnded(_ callID: String) {
        guard model.call?.id == callID else { return }
        model.call = nil
        activities.remove(id: callActivityID)
    }

    /// Answers as the call alert's buttons would. If that fails (the call
    /// just ended, or the alert changed), accepting opens the app instead.
    private func answer(_ call: IncomingCall, _ answer: CallAlerts.Answer) {
        #if DEBUG
        if call.id == Self.fakeCallID {
            callEnded(call.id)
            return
        }
        #endif
        if watcher.answer(call.id, answer) {
            callEnded(call.id)
        } else if answer == .accept, let url = NotificationApps.url(named: call.appName) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Clicks the banner while it's still there (the app opens on that
    /// notification), else opens the app.
    private func open(_ notification: BannerNotification) {
        if !watcher.press(notification.id), let url = NotificationApps.url(named: notification.appName) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        model.recent.remove(id: notification.id)
    }
}

@MainActor
@Observable
final class NotificationsModel {
    var recent = RecentNotifications()
    var call: IncomingCall?
}

// MARK: - Views

/// The sending app's icon, or a bell when it can't be found.
private struct NotificationAppIcon: View {
    let appName: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let appName, let icon = NotificationApps.icon(named: appName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "bell.fill")
                    .font(.islandSymbol(.compact, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Right wing: how many notifications are waiting, or a bell for one.
private struct NotificationCountView: View {
    var model: NotificationsModel

    var body: some View {
        let count = model.recent.items.count
        Group {
            if count > 1 {
                Text("\(count)")
                    .font(.islandCompact)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "bell.fill")
                    .font(.islandSymbol(.compact, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(count == 1 ? "1 notification" : "\(count) notifications")
    }
}

struct NotificationListView: View {
    var model: NotificationsModel
    var onOpen: (BannerNotification) -> Void

    /// The app's name, the title and the body, one line each.
    static let rowHeight: CGFloat = 52

    static func contentHeight(rows: Int) -> CGFloat {
        let shown = CGFloat(min(max(rows, 1), RecentNotifications.limit))
        return shown * rowHeight + (shown - 1) * IslandStyle.Spacing.xs + IslandStyle.Spacing.content
    }

    var body: some View {
        let items = model.recent.items
        if items.isEmpty {
            IslandEmptyState(title: "No new notifications", message: "Earlier ones are in Notification Center.")
        } else {
            VStack(spacing: IslandStyle.Spacing.xs) {
                ForEach(items) { notification in
                    NotificationRow(notification: notification) {
                        onOpen(notification)
                    }
                }
            }
            .islandContentMargins()
        }
    }
}

private struct NotificationRow: View {
    let notification: BannerNotification
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: IslandStyle.Spacing.m) {
                NotificationAppIcon(appName: notification.appName, size: IslandStyle.Size.control + IslandStyle.Spacing.xs)
                VStack(alignment: .leading, spacing: IslandStyle.Spacing.xxs) {
                    HStack {
                        Text(notification.appName)
                        Spacer(minLength: IslandStyle.Spacing.s)
                        Text(notification.receivedAt, style: .time)
                    }
                    .font(.islandCaption)
                    .foregroundStyle(.secondary)
                    Text(notification.title)
                        .font(.islandHeadline)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.islandCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, IslandStyle.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: NotificationListView.rowHeight, maxHeight: NotificationListView.rowHeight, alignment: .leading)
            .background(.island(isHovered ? .hover : .clear), in: RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: IslandStyle.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // Line the text up with other modules' content.
        .padding(.horizontal, -IslandStyle.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the notification")
    }

    /// Subtitle and body on one line.
    private var detail: String? {
        let parts = [notification.subtitle, notification.body].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}

/// Right wing while a call rings: a phone, pulsing (not under Reduce
/// Motion, or when nobody can see it).
private struct CallRingingSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.allowsAmbientAnimation) private var allowsAmbientAnimation

    var body: some View {
        Image(systemName: "phone.fill")
            .font(.islandSymbol(.compact, weight: .semibold))
            .foregroundStyle(IslandSignal.callAccept)
            .symbolEffect(.pulse, isActive: !reduceMotion && allowsAmbientAnimation)
            .accessibilityLabel("Incoming call")
    }
}

/// The open island while a call rings: who calls, then Decline and Accept,
/// in the order and colors of the macOS call alert.
struct IncomingCallView: View {
    let call: IncomingCall
    var onAnswer: (CallAlerts.Answer) -> Void

    static let rowHeight = IslandStyle.Size.playerControl
    static var contentHeight: CGFloat { rowHeight + IslandStyle.Spacing.content }

    var body: some View {
        HStack(spacing: IslandStyle.Spacing.m) {
            NotificationAppIcon(appName: call.appName, size: IslandStyle.Size.playerControl)
            VStack(alignment: .leading, spacing: IslandStyle.Spacing.xxs) {
                Text(call.caller)
                    .font(.islandHeadline)
                    .foregroundStyle(.primary)
                Text(call.detail ?? call.appName)
                    .font(.islandCaption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: IslandStyle.Spacing.s)
            HStack(spacing: IslandStyle.Spacing.m) {
                Button { onAnswer(.decline) } label: {
                    Label("Decline", systemImage: "phone.down.fill")
                }
                .buttonStyle(CallButtonStyle(color: IslandSignal.callDecline))
                Button { onAnswer(.accept) } label: {
                    Label("Accept", systemImage: "phone.fill")
                }
                .buttonStyle(CallButtonStyle(color: IslandSignal.callAccept))
            }
        }
        .frame(height: Self.rowHeight)
        .islandContentMargins()
    }
}

/// A round, filled call button; its symbol says what it does, its color
/// repeats it.
private struct CallButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        CallButtonBody(configuration: configuration, color: color)
    }
}

private struct CallButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let color: Color

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.islandSymbol(.control, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: IslandStyle.Size.playerControl, height: IslandStyle.Size.playerControl)
            .background(Circle().fill(color))
            .brightness(configuration.isPressed ? -0.15 : isHovered ? 0.08 : 0)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
    }
}
