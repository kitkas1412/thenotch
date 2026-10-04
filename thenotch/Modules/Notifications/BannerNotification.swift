//
//  BannerNotification.swift
//  thenotch
//

import Foundation

/// A notification read from a Notification Center banner: only what the
/// banner shows. With previews hidden (System Settings › Notifications ›
/// Show previews), macOS puts a placeholder in the banner's body, and so
/// does the island.
struct BannerNotification: Equatable, Identifiable, Sendable {
    /// The banner's accessibility identifier (a UUID per notification).
    let id: String
    /// The app that sent it, as Notification Center names it.
    let appName: String
    let title: String
    let subtitle: String?
    let body: String?
    let receivedAt: Date
}

/// A plain copy of part of Notification Center's accessibility tree, so
/// reading banners can be tested without it.
struct AXNode: Equatable, Sendable {
    var subrole: String?
    var identifier: String?
    var value: String?
    var description: String?
    /// Action names, as Accessibility gives them (`Name:Close\nTarget:…`).
    var actions: [String] = []
    var children: [AXNode] = []
}

/// Reads banners from Notification Center's windows (macOS 26). A banner
/// window holds `AXNotificationCenterBanner`s. Left alone: Notification
/// Center's own panel, which lists notifications in
/// `AXNotificationListItems`, and persistent banners
/// (`AXNotificationCenterAlert`, "Alerts" before macOS 15), which stay until
/// they're answered.
enum NotificationBanners {
    static let bannerSubrole = "AXNotificationCenterBanner"
    static let alertSubrole = "AXNotificationCenterAlert"
    static let listIdentifier = "AXNotificationListItems"
    /// Deep enough for the banner's texts: window › hosting view › group ›
    /// scroll area › banner › text.
    static let snapshotDepth = 6

    static func isBannerWindow(_ window: AXNode) -> Bool {
        var hasBanner = false
        var mustStay = false
        visit(window) { node in
            if node.subrole == bannerSubrole { hasBanner = true }
            if node.identifier == listIdentifier || node.subrole == alertSubrole { mustStay = true }
        }
        return hasBanner && !mustStay
    }

    static func banners(in window: AXNode, at date: Date) -> [BannerNotification] {
        var found: [BannerNotification] = []
        visit(window) { node in
            guard node.subrole == bannerSubrole, let id = node.identifier,
                  let appName = appName(fromDescription: node.description)
            else { return }
            // The texts the banner shows. Its description repeats them, but
            // in full even when previews are hidden: only the app's name is
            // taken from it.
            let title = text(identifier: "title", in: node)
            let subtitle = text(identifier: "subtitle", in: node)
            let body = text(identifier: "body", in: node)
            found.append(BannerNotification(
                id: id,
                appName: appName,
                title: title ?? appName,
                subtitle: subtitle,
                body: body,
                receivedAt: date
            ))
        }
        return found
    }

    /// "Messages, Anna, Hi there" → "Messages".
    static func appName(fromDescription description: String?) -> String? {
        guard let first = description?.components(separatedBy: ", ").first?
            .trimmingCharacters(in: .whitespaces), !first.isEmpty
        else { return nil }
        return first
    }

    static func text(identifier: String, in node: AXNode) -> String? {
        var found: String?
        visit(node) { child in
            if found == nil, child.identifier == identifier, let value = child.value, !value.isEmpty {
                found = value
            }
        }
        return found
    }

    static func visit(_ node: AXNode, _ body: (AXNode) -> Void) {
        body(node)
        for child in node.children { visit(child, body) }
    }
}

/// The notifications the island lists, newest first. Kept in memory only.
struct RecentNotifications: Equatable {
    static let limit = 3

    private(set) var items: [BannerNotification] = []

    /// Adds a notification, or updates the one with its id (a banner seen
    /// again as it changes). Returns whether it's new.
    @discardableResult
    mutating func add(_ notification: BannerNotification) -> Bool {
        if let index = items.firstIndex(where: { $0.id == notification.id }) {
            let receivedAt = items[index].receivedAt
            items[index] = BannerNotification(
                id: notification.id,
                appName: notification.appName,
                title: notification.title,
                subtitle: notification.subtitle,
                body: notification.body,
                receivedAt: receivedAt
            )
            return false
        }
        items.insert(notification, at: 0)
        if items.count > Self.limit {
            items.removeLast(items.count - Self.limit)
        }
        return true
    }

    mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    mutating func removeAll() {
        items.removeAll()
    }
}
