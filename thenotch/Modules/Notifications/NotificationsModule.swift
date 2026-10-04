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
@MainActor
final class NotificationsModule: IslandModule {
    let id = ModuleKind.notifications.id
    /// Above the battery and Bluetooth peeks, below a volume key just
    /// pressed.
    static let priority = 55
    /// How long a new notification keeps the island open: long enough to
    /// read a line, short enough not to stay in the way.
    static let peekDuration: TimeInterval = 2

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
        watcher.start()
    }

    func stop() {
        watcher.stop()
        watcher.onNotification = nil
        model.recent.removeAll()
        activities.remove(id: id)
    }

    func compactLeading() -> AnyView {
        AnyView(NotificationAppIcon(appName: model.recent.items.first?.appName, size: IslandStyle.Size.compactContent))
    }

    func compactTrailing() -> AnyView {
        AnyView(NotificationCountView(model: model))
    }

    func expandedView() -> AnyView {
        AnyView(NotificationListView(model: model) { [weak self] notification in
            self?.open(notification)
        })
    }

    /// Notifications not seen in the open island yet.
    var hasExpandedContent: Bool { !model.recent.items.isEmpty }

    var expandedContentHeight: CGFloat {
        NotificationListView.contentHeight(rows: model.recent.items.count)
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
