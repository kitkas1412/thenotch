//
//  ShelfModule.swift
//  thenotch
//

import AppKit
import os
import SwiftUI

/// Keeps files dropped on the notch at hand, across launches, for
/// `AppSettings.shelfLifetime`.
@MainActor
final class ShelfModule: FileDropReceiving {
    let id = ModuleKind.shelf.id
    /// Below Now Playing: a full shelf is a reminder, not news.
    static let priority = 5

    let store: ShelfStore
    /// Stack or list; the island opens on the stack.
    let presentation = ShelfPresentation()
    private let activities: ActivityCenter
    private let settings: AppSettings
    /// Where owned files (`DroppedFile.isOwned`) live.
    private let filesDirectory: URL
    private var isRunning = false
    private var isActivityPublished = false
    private var isObservingLifetime = false
    private var expiryTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    /// Items leaving now keep their owned files (see `onDraggedOut`).
    private var keepsOwnedFiles = false

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
            guard let self, !self.keepsOwnedFiles else { return }
            self.deleteOwnedFiles(of: items)
        }
    }

    func start() {
        isRunning = true
        let startedAt = Date.now
        // Read the saved shelf without holding up launch; housekeeping
        // needs it.
        Task { [weak self] in
            await self?.store.load()
            guard let self, self.isRunning else { return }
            self.deleteOrphanedFiles(createdBefore: startedAt)
            self.prune()
        }
        observeLifetime()
        // Saves are delayed; don't lose the last change when quitting.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.saveNow()
            }
        }
    }

    func stop() {
        isRunning = false
        store.saveNow()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        expiryTask?.cancel()
        expiryTask = nil
        activities.remove(id: id)
        isActivityPublished = false
    }

    func receive(_ files: [DroppedFile]) {
        let added = store.add(files)
        Log.drop.notice("Shelf added \(added) of \(files.count) file(s)")
        changed()
    }

    func islandDidExpand() {
        prune()
    }

    func islandDidCollapse() {
        presentation.showsAll = false
    }

    /// Files wait on the shelf. While files are dragged in, the island
    /// opens on the shelf regardless (it's pinned by the drag).
    var hasExpandedContent: Bool {
        !store.items.isEmpty
    }

    var expandedContentHeight: CGFloat {
        presentation.showsAll ? ShelfListView.contentHeight : ShelfStackView.contentHeight
    }

    /// The stack is a small square, like Dropover's shelf; the list takes
    /// the standard width.
    var expandedWidth: CGFloat {
        presentation.showsAll ? IslandState.expandedWidth : ShelfStackView.islandWidth
    }

    func compactLeading() -> AnyView {
        AnyView(
            Image(systemName: "tray.full.fill")
                .font(.islandSymbol(.compact, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        )
    }

    func compactTrailing() -> AnyView {
        AnyView(ShelfCountText(store: store))
    }

    func expandedView() -> AnyView {
        AnyView(ShelfView(store: store, presentation: presentation, actions: ShelfActions(
            airDrop: { AirDrop.send($0) },
            open: { NSWorkspace.shared.open($0.url) },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting($0.map(\.url)) },
            remove: { [weak self] item in
                self?.store.remove(item.id)
                self?.changed()
            },
            draggedOut: { [weak self] items, outcome in
                guard let self else { return }
                Log.drop.notice("\(items.count) shelf file(s) were dropped elsewhere (\(String(describing: outcome), privacy: .public)); removing them from the shelf")
                // A copy was dropped: the app may still be reading the
                // file (a browser uploads it after the drop), so an owned
                // file is left for the cleanup at the next launch.
                self.keepsOwnedFiles = outcome == .copied
                self.store.remove(Set(items.map(\.id)))
                self.keepsOwnedFiles = false
                self.changed()
            },
            clear: { [weak self] in
                self?.store.removeAll()
                self?.changed()
            }
        )))
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
    /// zone, dragged out to an app, or left over after a crash. Only folders from before `date`:
    /// a file dropped since may not have reached the shelf yet. Runs in the
    /// background.
    private func deleteOrphanedFiles(createdBefore date: Date) {
        let kept = Set(store.items.filter(\.isOwned).map { $0.url.deletingLastPathComponent().standardizedFileURL.path })
        let directory = filesDirectory
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let folders = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
            for folder in folders where !kept.contains(folder.standardizedFileURL.path) {
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                if created < date {
                    try? fileManager.removeItem(at: folder)
                }
            }
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
