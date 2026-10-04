//
//  NotificationBannerTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct NotificationBannerTests {
    static let date = Date(timeIntervalSince1970: 1_000)

    /// A banner as macOS 26 shows it.
    static func banner(id: String = "B1", description: String?, title: String?, subtitle: String? = nil, body: String?) -> AXNode {
        var texts: [AXNode] = []
        if let title { texts.append(AXNode(identifier: "title", value: title)) }
        if let subtitle { texts.append(AXNode(identifier: "subtitle", value: subtitle)) }
        if let body { texts.append(AXNode(identifier: "body", value: body)) }
        return AXNode(subrole: NotificationBanners.bannerSubrole, identifier: id, description: description, children: texts)
    }

    /// Window › hosting view › group › scroll area › content.
    static func window(_ content: [AXNode]) -> AXNode {
        AXNode(subrole: "AXSystemDialog", children: [
            AXNode(subrole: "AXHostingView", children: [
                AXNode(children: [
                    AXNode(children: content),
                    AXNode(identifier: "widgets-overlay-view"),
                ]),
            ]),
        ])
    }

    @Test func readsABanner() throws {
        let window = Self.window([Self.banner(description: "Messages, Anna, Lunch?, See you at noon", title: "Anna", subtitle: "Lunch?", body: "See you at noon")])
        #expect(NotificationBanners.isBannerWindow(window))
        let banners = NotificationBanners.banners(in: window, at: Self.date)
        #expect(banners == [BannerNotification(id: "B1", appName: "Messages", title: "Anna", subtitle: "Lunch?", body: "See you at noon", receivedAt: Self.date)])
    }

    /// With previews hidden the banner's body is a placeholder, but its
    /// description still has the text: only the shown texts are used.
    @Test func hiddenPreviewsKeepTheTextHidden() throws {
        let window = Self.window([Self.banner(description: "Messages, Anna, Secret", title: "Anna", body: "Notification")])
        let banner = try #require(NotificationBanners.banners(in: window, at: Self.date).first)
        #expect(banner.body == "Notification")
        #expect(banner.appName == "Messages")
        #expect(!"\(banner)".contains("Secret"))
    }

    @Test func aBannerWithoutTitleUsesTheAppName() throws {
        let window = Self.window([Self.banner(description: "Calendar", title: nil, body: nil)])
        let banner = try #require(NotificationBanners.banners(in: window, at: Self.date).first)
        #expect(banner.title == "Calendar")
        #expect(banner.body == nil)
    }

    @Test func notificationCenterPanelIsNotABannerWindow() {
        let stack = AXNode(subrole: "AXNotificationCenterBannerStack", identifier: "B1", description: "Messages, Anna, stacked")
        let panel = Self.window([AXNode(identifier: NotificationBanners.listIdentifier, children: [stack])])
        #expect(!NotificationBanners.isBannerWindow(panel))
        // Even if it lists a plain banner.
        let mixed = Self.window([AXNode(identifier: NotificationBanners.listIdentifier, children: [Self.banner(description: "Messages", title: "Anna", body: nil)])])
        #expect(!NotificationBanners.isBannerWindow(mixed))
    }

    /// Persistent banners stay until they're answered, even beside a
    /// temporary one.
    @Test func persistentBannersAreLeftAlone() {
        let alert = AXNode(subrole: NotificationBanners.alertSubrole, identifier: "A1", description: "Reminders, Call Anna")
        #expect(!NotificationBanners.isBannerWindow(Self.window([alert])))
        #expect(!NotificationBanners.isBannerWindow(Self.window([alert, Self.banner(description: "Mail", title: "Hi", body: nil)])))
    }

    @Test func aWindowWithoutBannersIsLeftAlone() {
        #expect(!NotificationBanners.isBannerWindow(Self.window([])))
    }

    @Test func appNameIsTheDescriptionsFirstPart() {
        #expect(NotificationBanners.appName(fromDescription: "Script Editor, Title, Body") == "Script Editor")
        #expect(NotificationBanners.appName(fromDescription: "Mail") == "Mail")
        #expect(NotificationBanners.appName(fromDescription: "") == nil)
        #expect(NotificationBanners.appName(fromDescription: nil) == nil)
    }

    @Test func bannersWithoutIdOrDescriptionAreSkipped() {
        let noID = AXNode(subrole: NotificationBanners.bannerSubrole, description: "Mail")
        let noDescription = Self.banner(description: nil, title: "Hi", body: nil)
        #expect(NotificationBanners.banners(in: Self.window([noID, noDescription]), at: Self.date).isEmpty)
    }
}

struct RecentNotificationsTests {
    static func notification(_ id: String, title: String = "T", at seconds: TimeInterval = 0) -> BannerNotification {
        BannerNotification(id: id, appName: "Mail", title: title, subtitle: nil, body: nil, receivedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func newestFirstUpToTheLimit() {
        var recent = RecentNotifications()
        for index in 0..<(RecentNotifications.limit + 2) {
            let isNew = recent.add(Self.notification("N\(index)"))
            #expect(isNew)
        }
        #expect(recent.items.count == RecentNotifications.limit)
        #expect(recent.items.first?.id == "N\(RecentNotifications.limit + 1)")
    }

    /// A banner seen again (its window changed) updates it in place.
    @Test func sameIdUpdatesWithoutBeingNew() {
        var recent = RecentNotifications()
        recent.add(Self.notification("A", at: 1))
        recent.add(Self.notification("B", at: 2))
        let isNew = recent.add(Self.notification("A", title: "Changed", at: 3))
        #expect(!isNew)
        #expect(recent.items.map(\.id) == ["B", "A"])
        #expect(recent.items[1].title == "Changed")
        #expect(recent.items[1].receivedAt == Date(timeIntervalSince1970: 1))
    }

    @Test func removing() {
        var recent = RecentNotifications()
        recent.add(Self.notification("A"))
        recent.add(Self.notification("B"))
        recent.remove(id: "A")
        #expect(recent.items.map(\.id) == ["B"])
        recent.removeAll()
        #expect(recent.items.isEmpty)
    }
}

@MainActor
struct NotificationListLayoutTests {
    @Test func aFullListFitsThePanel() {
        // The tallest notch (38 pt), the margin below it, and the tab row.
        let island = NotificationListView.contentHeight(rows: RecentNotifications.limit) + 38 + IslandStyle.Spacing.content + IslandState.tabRowHeight
        #expect(island <= IslandController.panelSize.height)
    }
}

struct CallAlertTests {
    static let accept = "Name:Accept\nTarget:0x0\nSelector:(null)"
    static let decline = "Name:Decline\nTarget:0x0\nSelector:(null)"

    static func alert(id: String = "C1", description: String? = "FaceTime, Anna, FaceTime Audio", actions: [String] = [accept, decline, "AXPress"], title: String? = "Anna", subtitle: String? = "FaceTime Audio") -> AXNode {
        var texts: [AXNode] = []
        if let title { texts.append(AXNode(identifier: "title", value: title)) }
        if let subtitle { texts.append(AXNode(identifier: "subtitle", value: subtitle)) }
        return AXNode(subrole: NotificationBanners.alertSubrole, identifier: id, description: description, actions: actions, children: texts)
    }

    @Test func readsACall() throws {
        let window = NotificationBannerTests.window([Self.alert()])
        #expect(CallAlerts.call(in: window) == IncomingCall(id: "C1", appName: "FaceTime", caller: "Anna", detail: "FaceTime Audio"))
        // Still a persistent alert, not a banner window.
        #expect(!NotificationBanners.isBannerWindow(window))
    }

    @Test func findsTheActionsToAnswer() {
        let alert = Self.alert()
        #expect(CallAlerts.action(.accept, in: alert) == Self.accept)
        #expect(CallAlerts.action(.decline, in: alert) == Self.decline)
    }

    /// A reminder or other persistent alert has no answer actions.
    @Test func otherAlertsAreNotCalls() {
        let reminder = Self.alert(actions: ["Name:Complete\nTarget:0x0\nSelector:(null)", "AXPress"])
        #expect(CallAlerts.call(in: NotificationBannerTests.window([reminder])) == nil)
        let acceptOnly = Self.alert(actions: [Self.accept])
        #expect(CallAlerts.call(in: NotificationBannerTests.window([acceptOnly])) == nil)
    }

    @Test func aCallNeedsItsCaller() {
        #expect(CallAlerts.call(in: NotificationBannerTests.window([Self.alert(title: nil)])) == nil)
    }

    @Test func actionNames() {
        #expect(CallAlerts.actionName(Self.accept) == "Accept")
        #expect(CallAlerts.actionName("Name:Chấp nhận") == "Chấp nhận")
        #expect(CallAlerts.actionName("AXPress") == nil)
        #expect(CallAlerts.actionName("Name:") == nil)
    }
}

@MainActor
struct IncomingCallLayoutTests {
    @Test func theCallFitsThePanel() {
        let island = IncomingCallView.contentHeight + 38 + IslandStyle.Spacing.content + IslandState.tabRowHeight
        #expect(island <= IslandController.panelSize.height)
    }
}
