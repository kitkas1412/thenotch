//
//  ClipboardTool.swift
//  thenotch
//

import AppKit
import Observation

/// Clipboard history: records copies, keeps them encrypted on disk, and
/// pastes one back on request. The shortcut opens it in the island.
@MainActor
@Observable
final class ClipboardTool: Tool {
    @ObservationIgnored let id = ToolKind.clipboard.id
    /// Replaced by a fresh, empty one when the tool stops, so the history
    /// isn't kept in memory while the tool is off (the files stay).
    private(set) var store: ClipboardStore
    private(set) var monitor: ClipboardMonitor
    private(set) var paster: ClipboardPaster
    /// The running tool, for the menu panel and Settings, which don't own
    /// the `ToolHost`. `nil` while the tool is off.
    private(set) static weak var current: ClipboardTool?

    /// True while the tool is on.
    private(set) var isRunning = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotKeys: HotKeyCenter
    @ObservationIgnored private let contributions: IslandContributions
    @ObservationIgnored private var islandModule: ClipboardIslandModule?
    @ObservationIgnored private var hostObservation = 0
    @ObservationIgnored private var observation: ShortcutObservation?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var limitObservation = 0
    /// The app that was in front when the history opened: where to paste.
    @ObservationIgnored private var pasteTarget: NSRunningApplication?

    init(settings: AppSettings, hotKeys: HotKeyCenter, contributions: IslandContributions) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.contributions = contributions
        let parts = Self.makeParts(settings: settings)
        store = parts.store
        monitor = parts.monitor
        paster = parts.paster
    }

    private static func makeParts(settings: AppSettings) -> (
        store: ClipboardStore, monitor: ClipboardMonitor, paster: ClipboardPaster
    ) {
        let store = ClipboardStore(
            persistence: .standard, keyProvider: KeychainKeyStore(), limit: settings.clipboardLimit)
        let monitor = ClipboardMonitor(store: store, settings: settings)
        return (store, monitor, ClipboardPaster(store: store, settings: settings, monitor: monitor))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let module = ClipboardIslandModule(tool: self, contributions: contributions)
        islandModule = module
        contributions.add(module)
        Self.current = self
        register()
        observeHost()
        observation = settings.observeShortcuts { [weak self] actionID in
            if actionID == ShortcutAction.clipboardShowHistory.id { self?.register() }
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.willTerminate() }
        }
        observeLimit()
        let store = store, monitor = monitor
        startTask = Task { [weak self] in
            await store.load()
            guard !Task.isCancelled, let self else { return }
            // The last run quit without clearing (a crash, a force quit),
            // maybe with files that couldn't be read (no key).
            if settings.clipboardClearOnQuit {
                let hasFiles = await store.hasSavedFiles()
                guard !Task.isCancelled else { return }
                if hasFiles || !store.items.isEmpty {
                    await store.clear()?.value
                    guard !Task.isCancelled else { return }
                }
            }
            monitor.start()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        contributions.remove(id: id)
        islandModule = nil
        hostObservation += 1
        if Self.current === self { Self.current = nil }
        startTask?.cancel()
        startTask = nil
        monitor.stop()
        observation?.cancel()
        observation = nil
        hotKeys.unregister(id: ShortcutAction.clipboardShowHistory.id)
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
        terminateObserver = nil
        limitObservation += 1
        pasteTarget = nil
        if settings.clipboardClearOnQuit {
            // The quit won't reach a stopped tool, and the history would be
            // cleared on quit anyway: clear it now, so nothing survives.
            store.clearNow()
        } else {
            store.saveNow()
        }
        // A load or a key replacement under way must not touch the disk
        // or the Keychain once the new store is in place.
        store.discard()
        ClipboardThumbnails.shared.removeAll()
        let parts = Self.makeParts(settings: settings)
        store = parts.store
        monitor = parts.monitor
        paster = parts.paster
    }

    // MARK: For the island

    /// Opens, selects or closes the history in the island. Beeps if the
    /// island isn't running (Notch is off).
    func showHistory() {
        guard isRunning, contributions.show(id) else {
            NSSound.beep()
            return
        }
    }

    /// Remembers the app that was in front when the history opened (thenotch
    /// itself doesn't count): `paste` goes there.
    func historyOpened(frontmost: NSRunningApplication?) {
        let isSelf = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        pasteTarget = isSelf ? nil : frontmost
    }

    /// Pastes the entry into the remembered app. Call it after the island
    /// closed. `.copied` means ⌘V wasn't sent: say "Copied — press ⌘V".
    func paste(_ item: ClipboardItem, asPlainText: Bool) async -> ClipboardPaster.Result {
        await paster.paste(item, asPlainText: asPlainText, into: pasteTarget)
    }

    /// How `clearStoredHistory()` went.
    enum ClearResult: Equatable {
        case cleared
        /// Some files are still there.
        case filesNotDeleted
        /// The files are gone, the key isn't.
        case keyNotDeleted

        /// What Settings says, `nil` when it worked.
        var problem: String? {
            switch self {
            case .cleared: nil
            case .filesNotDeleted: "Some saved history couldn't be deleted. Try again."
            case .keyNotDeleted: "History was deleted, but its key couldn't be removed from the keychain."
            }
        }
    }

    /// Deletes the saved history and its key without the tool running
    /// (Settings › Clear History while the tool is off), after any write
    /// still queued, off the main thread. The next start creates a new key.
    static func clearStoredHistory() async -> ClearResult {
        ClipboardThumbnails.shared.removeAll()
        let provider = KeychainKeyStore()
        let result = await ClipboardPersistence.standard.wipeInBackground {
            try provider.delete()
            return nil
        }
        if !result.filesRemoved { return .filesNotDeleted }
        return result.keyError == nil ? .cleared : .keyNotDeleted
    }

    // MARK: Private

    private func register() {
        let id = ShortcutAction.clipboardShowHistory.id
        // Without the island the shortcut would do nothing: leave the key to other apps.
        guard contributions.isHostAvailable, let shortcut = settings.shortcut(for: id) else {
            hotKeys.unregister(id: id)
            return
        }
        hotKeys.register(id: id, shortcut: shortcut) { [weak self] in
            self?.showHistory()
        }
    }

    private func willTerminate() {
        if settings.clipboardClearOnQuit {
            // Synchronous: the process exits right after.
            store.clearNow()
        } else {
            store.saveNow()
        }
    }

    /// Registers the shortcut while the island runs; re-arms itself until
    /// `stop()` bumps the generation.
    private func observeHost() {
        let generation = hostObservation
        withObservationTracking {
            _ = contributions.isHostAvailable
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, isRunning, hostObservation == generation else { return }
                register()
                observeHost()
            }
        }
    }

    /// Re-arms itself until `stop()` bumps the generation.
    private func observeLimit() {
        let generation = limitObservation
        withObservationTracking {
            _ = settings.clipboardLimit
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, isRunning, limitObservation == generation else { return }
                store.setLimit(settings.clipboardLimit)
                observeLimit()
            }
        }
    }
}
