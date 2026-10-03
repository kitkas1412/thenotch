//
//  ShelfModule.swift
//  thenotch
//

import AppKit
import SwiftUI

/// Keeps files dropped on the notch at hand, across launches, for
/// `AppSettings.shelfLifetime`.
@MainActor
final class ShelfModule: FileDropReceiving {
    let id = ModuleKind.shelf.id
    /// Below Now Playing: a full shelf is a reminder, not news.
    static let priority = 5

    let store: ShelfStore
    private let activities: ActivityCenter
    private let settings: AppSettings
    /// Where owned files (`DroppedFile.isOwned`) live.
    private let filesDirectory: URL
    private var isRunning = false
    private var isActivityPublished = false
    private var isObservingLifetime = false
    private var expiryTask: Task<Void, Never>?

    init(
        activities: ActivityCenter,
        settings: AppSettings,
        persistence: ShelfPersistence? = .standard,
        filesDirectory: URL = FileDrop.directory
    ) {
        self.activities = activities
        self.settings = settings
        self.filesDirectory = filesDirectory
        store = ShelfStore(persistence: persistence)
        store.onRemove = { [weak self] items in
            self?.deleteOwnedFiles(of: items)
        }
    }

    func start() {
        isRunning = true
        deleteOrphanedFiles()
        prune()
        observeLifetime()
    }

    func stop() {
        isRunning = false
        expiryTask?.cancel()
        expiryTask = nil
        activities.remove(id: id)
        isActivityPublished = false
    }

    func receive(_ files: [DroppedFile]) {
        store.add(files)
        changed()
    }

    func islandDidExpand() {
        prune()
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
            onAdd: { [weak self] in self?.receive($0) },
            onAirDrop: { AirDrop.send($0) },
            onOpen: { NSWorkspace.shared.open($0.url) },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0.url]) },
            onRemove: { [weak self] item in
                self?.store.remove(item.id)
                self?.changed()
            },
            onClear: { [weak self] in
                self?.store.removeAll()
                self?.changed()
            }
        ))
    }

    // MARK: - Housekeeping

    /// Drops files that vanished or expired.
    private func prune() {
        store.removeMissing()
        store.removeExpired(lifetime: settings.shelfLifetime.interval)
        changed()
    }

    private func changed() {
        updateActivity()
        scheduleExpiry()
    }

    /// Prunes when the oldest item expires: one sleeping task, no polling.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard isRunning, let next = store.nextExpiry(lifetime: settings.shelfLifetime.interval) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 1))
            guard let self, !Task.isCancelled else { return }
            self.prune()
        }
    }

    /// Prunes again whenever the lifetime is changed in Settings.
    private func observeLifetime() {
        guard !isObservingLifetime else { return }
        isObservingLifetime = true
        withObservationTracking {
            _ = settings.shelfLifetime
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isObservingLifetime = false
                if self.isRunning {
                    self.prune()
                    self.observeLifetime()
                }
            }
        }
    }

    /// Owned files are saved as `filesDirectory/<uuid>/<name>`; delete that
    /// folder, never anything outside `filesDirectory`.
    private func deleteOwnedFiles(of items: [ShelfItem]) {
        for item in items where item.isOwned {
            let folder = item.url.deletingLastPathComponent()
            if Self.isFolder(folder, directlyIn: filesDirectory) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    /// Deletes saved files no shelf item refers to: dropped on the AirDrop
    /// zone, or left over after a crash.
    private func deleteOrphanedFiles() {
        let kept = Set(store.items.filter(\.isOwned).map { $0.url.deletingLastPathComponent().standardizedFileURL.path })
        let folders = (try? FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !kept.contains(folder.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static func isFolder(_ folder: URL, directlyIn directory: URL) -> Bool {
        folder.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
    }

    /// Shows the shelf beside the notch while it holds files.
    private func updateActivity() {
        let hasItems = isRunning && !store.items.isEmpty
        guard hasItems != isActivityPublished else { return }
        isActivityPublished = hasItems
        if hasItems {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.priority))
        } else {
            activities.remove(id: id)
        }
    }
}
