//
//  ShelfModule.swift
//  thenotch
//

import AppKit
import SwiftUI

/// Keeps files dropped on the notch at hand.
@MainActor
final class ShelfModule: FileDropReceiving {
    let id = ModuleKind.shelf.id
    /// Below Now Playing: a full shelf is a reminder, not news.
    static let priority = 5

    let store = ShelfStore()
    private let activities: ActivityCenter
    private var isActivityPublished = false

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        updateActivity()
    }

    func stop() {
        activities.remove(id: id)
        isActivityPublished = false
    }

    func receive(_ urls: [URL]) {
        store.add(urls)
        updateActivity()
    }

    func islandDidExpand() {
        store.removeMissing()
        updateActivity()
    }

    func compactLeading() -> AnyView {
        AnyView(
            Image(systemName: "tray.full.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        )
    }

    func compactTrailing() -> AnyView {
        AnyView(ShelfCountText(store: store))
    }

    func expandedView() -> AnyView {
        AnyView(ShelfExpandedView(
            store: store,
            onOpen: { NSWorkspace.shared.open($0.url) },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0.url]) },
            onRemove: { [weak self] item in
                self?.store.remove(item.id)
                self?.updateActivity()
            },
            onClear: { [weak self] in
                self?.store.removeAll()
                self?.updateActivity()
            }
        ))
    }

    /// Shows the shelf beside the notch while it holds files.
    private func updateActivity() {
        let hasItems = !store.items.isEmpty
        guard hasItems != isActivityPublished else { return }
        isActivityPublished = hasItems
        if hasItems {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.priority))
        } else {
            activities.remove(id: id)
        }
    }
}
