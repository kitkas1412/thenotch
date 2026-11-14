//
//  ClipboardTool.swift
//  thenotch
//

import AppKit
import Observation

/// What the Clipboard tool needs from the history panel (the UI implements
/// it and sets `ClipboardTool.presenter`).
@MainActor
protocol ClipboardPanelPresenting: AnyObject {
    /// Show the history panel (the shortcut was pressed). The tool has
    /// already remembered the frontmost app (`historyOpened(frontmost:)`).
    func showClipboardHistory()
}

/// Clipboard history: records copies, keeps them encrypted on disk, and
/// pastes one back on request. The shortcut opens the panel.
@MainActor
@Observable
final class ClipboardTool: Tool {
    @ObservationIgnored let id = ToolKind.clipboard.id
    /// Replaced by a fresh, empty one when the tool stops, so the history
    /// isn't kept in memory while the tool is off (the files stay).
    private(set) var store: ClipboardStore
    private(set) var monitor: ClipboardMonitor
    private(set) var paster: ClipboardPaster
    /// Implemented by the history panel; `nil` until it exists.
    @ObservationIgnored weak var presenter: ClipboardPanelPresenting?
    /// Keeps the history panel alive while the tool runs (`presenter` is weak).
    @ObservationIgnored private var panelController: ClipboardPanelController?
    /// The running tool, for the menu panel and Settings, which don't own
    /// the `ToolHost`. `nil` while the tool is off.
    private(set) static weak var current: ClipboardTool?

    /// True while the tool is on.
    private(set) var isRunning = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotKeys: HotKeyCenter
    @ObservationIgnored private var observation: ShortcutObservation?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var limitObservation = 0
    /// The app that was in front when the history opened: where to paste.
    @ObservationIgnored private var pasteTarget: NSRunningApplication?

    init(settings: AppSettings, hotKeys: HotKeyCenter) {
        self.settings = settings
        self.hotKeys = hotKeys
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
        let controller = ClipboardPanelController(tool: self)
        panelController = controller
        presenter = controller
        Self.current = self
        register()
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
        panelController?.close()
        panelController = nil
        presenter = nil
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

    // MARK: For the panel

    /// Opens the history panel through `presenter`, remembering the app to
    /// paste into. Beeps if there is no panel yet.
    func showHistory() {
        guard isRunning, let presenter else {
            NSSound.beep()
            return
        }
        historyOpened(frontmost: NSWorkspace.shared.frontmostApplication)
        presenter.showClipboardHistory()
    }

    /// Remembers the app that was in front when the history opened (thenotch
    /// itself doesn't count): `paste` goes there.
    func historyOpened(frontmost: NSRunningApplication?) {
        let isSelf = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        pasteTarget = isSelf ? nil : frontmost
    }

    /// Pastes the entry into the remembered app. Call it after the panel
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
        guard let shortcut = settings.shortcut(for: id) else {
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
