//
//  IncomingCall.swift
//  thenotch
//

import Foundation

/// A call ringing on this Mac (FaceTime, or an iPhone call relayed by
/// Continuity), read from Notification Center's call alert: only what the
/// alert shows.
struct IncomingCall: Equatable, Identifiable, Sendable {
    /// The alert's accessibility identifier.
    let id: String
    /// The app ringing, as Notification Center names it ("FaceTime").
    let appName: String
    /// Who calls: the alert's title (a contact's name or a number).
    let caller: String
    /// The kind of call ("FaceTime Audio", "iPhone"…), if the alert says.
    let detail: String?
}

/// Reads call alerts from Notification Center's windows. A call alert is
/// a persistent banner (`AXNotificationCenterAlert`) with an action to
/// answer and one to decline; performing them is the same as clicking the
/// alert's buttons.
///
/// The action names below are guesses until checked against a real call
/// (FaceTime and Continuity); they are localized, so each language macOS
/// may run in needs its own.
enum CallAlerts {
    enum Answer {
        case accept, decline
    }

    static let acceptNames: Set<String> = ["Accept", "Answer", "Chấp nhận", "Trả lời"]
    static let declineNames: Set<String> = ["Decline", "Từ chối"]

    /// The call in a Notification Center window, if it holds a call alert.
    static func call(in window: AXNode) -> IncomingCall? {
        var found: IncomingCall?
        NotificationBanners.visit(window) { node in
            guard found == nil, node.subrole == NotificationBanners.alertSubrole,
                  let id = node.identifier,
                  action(.accept, in: node) != nil, action(.decline, in: node) != nil,
                  let appName = NotificationBanners.appName(fromDescription: node.description),
                  let caller = NotificationBanners.text(identifier: "title", in: node)
            else { return }
            found = IncomingCall(
                id: id,
                appName: appName,
                caller: caller,
                detail: NotificationBanners.text(identifier: "subtitle", in: node) ?? NotificationBanners.text(identifier: "body", in: node)
            )
        }
        return found
    }

    /// The full action name (as given to `AXUIElementPerformAction`) that
    /// answers the alert that way.
    static func action(_ answer: Answer, in alert: AXNode) -> String? {
        let names = answer == .accept ? acceptNames : declineNames
        return alert.actions.first { actionName($0).map(names.contains) ?? false }
    }

    /// "Name:Accept\nTarget:0x0\nSelector:(null)" → "Accept". Standard
    /// actions (`AXPress`) have no name.
    static func actionName(_ action: String) -> String? {
        guard action.hasPrefix("Name:") else { return nil }
        let name = action.dropFirst("Name:".count).prefix { $0 != "\n" }
        return name.isEmpty ? nil : String(name)
    }
}
