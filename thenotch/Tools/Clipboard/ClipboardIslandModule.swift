//
//  ClipboardIslandModule.swift
//  thenotch
//

import AppKit
import Observation
import SwiftUI

/// The clipboard history as an island module, contributed by `ClipboardTool`
/// while it runs. Shown by the shortcut (pinned), it takes typing, stays out
/// of screenshots, and a finished choice peeks beside the notch.
@MainActor
final class ClipboardIslandModule: ContributedIslandModule {
    let id = ToolKind.clipboard.id

    /// Notch (38) + margin (24) + tab row (40) + this ≤ the panel's 320.
    static let contentHeight: CGFloat = 216
    private static let peekDuration: TimeInterval = 2
    private static let peekPriority = 55

    private unowned let tool: ClipboardTool
    private let contributions: IslandContributions
    private var activities: ActivityCenter?
    /// One per opening, so each opening starts fresh.
    private var model: ClipboardHistoryModel?
    private let peek = ClipboardPeekModel()

    init(tool: ClipboardTool, contributions: IslandContributions) {
        self.tool = tool
        self.contributions = contributions
    }

    // MARK: ContributedIslandModule

    func attach(activities: ActivityCenter) {
        self.activities = activities
    }

    func detach() {
        activities?.remove(id: id)
        activities = nil
        model = nil
    }

    // MARK: IslandModule

    /// The tool owns the work; the island doesn't start or stop it.
    func start() {}
    func stop() {}

    var tabTitle: String { ToolKind.clipboard.title }
    var tabSymbol: String { ToolKind.clipboard.symbol }
    var takesKeyboard: Bool { true }
    var excludesFromCapture: Bool { true }
    var expandedWidth: CGFloat { 600 }
    var expandedContentHeight: CGFloat { Self.contentHeight }

    var hasExpandedContent: Bool {
        tool.store.isLoaded && !tool.store.items.isEmpty
    }

    func islandDidExpand() {
        // The island never activates thenotch: the frontmost app is where to paste.
        tool.historyOpened(frontmost: NSWorkspace.shared.frontmostApplication)
        let model = ClipboardHistoryModel(tool: tool)
        model.onChoose = { [weak self] item, plain in self?.choose(item, asPlainText: plain) }
        model.onClose = { [weak self] in self?.contributions.close() }
        self.model = model
    }

    func islandDidCollapse() {
        model = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        model?.handle(event) ?? false
    }

    func compactLeading() -> AnyView {
        AnyView(ClipboardPeekSymbol(peek: peek))
    }

    func compactTrailing() -> AnyView {
        AnyView(ClipboardPeekTrailing(peek: peek))
    }

    func expandedView() -> AnyView {
        guard let model else { return AnyView(EmptyView()) }
        return AnyView(ClipboardHistoryView(model: model))
    }

    // MARK: Choosing

    private func choose(_ item: ClipboardItem, asPlainText: Bool) {
        // Releases the keyboard before ⌘V can be sent.
        contributions.close()
        let tool = tool
        Task { [weak self] in
            switch await tool.paste(item, asPlainText: asPlainText) {
            case .pasted: break
            case .copied: self?.show(.copied)
            case .unavailable: self?.show(.unavailable)
            }
        }
    }

    private func show(_ outcome: ClipboardPeekModel.Outcome) {
        guard let activities else { return }
        peek.outcome = outcome
        activities.publish(LiveActivity(
            id: id,
            moduleID: id,
            priority: Self.peekPriority,
            expiresAt: .now.addingTimeInterval(Self.peekDuration)
        ))
        // Status text that VoiceOver should say without moving focus.
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: outcome.message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

@MainActor
@Observable
final class ClipboardPeekModel {
    enum Outcome {
        case copied, unavailable

        var symbol: String {
            switch self {
            case .copied: "doc.on.clipboard"
            case .unavailable: "exclamationmark.triangle"
            }
        }

        var message: String {
            switch self {
            case .copied: "Copied — press ⌘V"
            case .unavailable: "Item no longer available"
            }
        }
    }

    var outcome: Outcome = .copied
}

private struct ClipboardPeekSymbol: View {
    var peek: ClipboardPeekModel

    var body: some View {
        Image(systemName: peek.outcome.symbol)
            .font(.islandSymbol(.compact, weight: .semibold))
            .foregroundStyle(peek.outcome == .copied ? AnyShapeStyle(.primary) : AnyShapeStyle(IslandSignal.critical))
            .accessibilityHidden(true)
    }
}

private struct ClipboardPeekTrailing: View {
    var peek: ClipboardPeekModel

    var body: some View {
        if peek.outcome == .copied {
            Text("⌘V")
                .font(.islandCompact)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }
}
