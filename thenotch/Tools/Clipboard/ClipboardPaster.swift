//
//  ClipboardPaster.swift
//  thenotch
//

import AppKit
import Carbon.HIToolbox

/// Puts a history entry back on the pasteboard and, when allowed, presses
/// ⌘V in the app that was in front.
@MainActor
final class ClipboardPaster {
    enum Result: Equatable {
        /// On the pasteboard and ⌘V was sent.
        case pasted
        /// On the pasteboard only: the UI says "Copied — press ⌘V".
        case copied
        /// Nothing to paste (the image or the files are gone).
        case unavailable
    }

    private let store: ClipboardStore
    private let settings: AppSettings
    private let monitor: ClipboardMonitor
    private let pasteboard: NSPasteboard

    /// The change count of our last write; the monitor skips it.
    private(set) var lastOwnChangeCount: Int?

    init(
        store: ClipboardStore, settings: AppSettings, monitor: ClipboardMonitor,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.settings = settings
        self.monitor = monitor
        self.pasteboard = pasteboard
    }

    /// Call after the panel closed. `app` is the app to paste into.
    func paste(
        _ item: ClipboardItem, asPlainText: Bool, into app: NSRunningApplication?
    ) async -> Result {
        guard await write(item, asPlainText: asPlainText) else { return .unavailable }
        store.markUsed(item.id)
        // No target (thenotch was in front, or it quit): ⌘V would land in
        // whatever is in front now.
        guard settings.clipboardPastesDirectly,
              AccessibilityPermission.isTrusted,
              let app, !app.isTerminated,
              !IsSecureEventInputEnabled() else { return .copied }
        try? await Task.sleep(for: .milliseconds(50))
        if !app.isActive {
            app.activate()
            let deadline = ContinuousClock.now + .milliseconds(500)
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier,
                  ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        // Checked again right before: a password field may have taken the
        // keyboard, or another app come in front, meanwhile.
        guard Self.maySendPaste(
            targetPID: app.isTerminated ? nil : app.processIdentifier,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            secureInput: IsSecureEventInputEnabled()
        ) else { return .copied }
        return Self.postPaste() ? .pasted : .copied
    }

    /// ⌘V goes only to the remembered app, in front, with Secure Input off.
    nonisolated static func maySendPaste(targetPID: pid_t?, frontmostPID: pid_t?, secureInput: Bool) -> Bool {
        guard let targetPID, !secureInput else { return false }
        return frontmostPID == targetPID
    }

    // MARK: Writing

    private func write(_ item: ClipboardItem, asPlainText: Bool) async -> Bool {
        let marker = NSPasteboard.PasteboardType(monitor.ownMarkerType)
        var objects: [NSPasteboardItem] = []
        switch item.content {
        case .text(let plain, let rtf, let html):
            let entry = NSPasteboardItem()
            entry.setString(plain, forType: .string)
            if !asPlainText {
                if let rtf { entry.setData(rtf, forType: .rtf) }
                if let html { entry.setData(html, forType: .html) }
            }
            objects = [entry]
        case .image(_, _, let uti, _):
            guard let bytes = await store.imageData(for: item) else { return false }
            let entry = NSPasteboardItem()
            entry.setData(bytes, forType: NSPasteboard.PasteboardType(uti))
            objects = [entry]
        case .files(let paths):
            let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { return false }
            if asPlainText {
                let entry = NSPasteboardItem()
                entry.setString(existing.joined(separator: "\n"), forType: .string)
                objects = [entry]
            } else {
                objects = existing.map { path in
                    let entry = NSPasteboardItem()
                    entry.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                    return entry
                }
            }
        }
        objects[0].setData(Data(), forType: marker)
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else { return false }
        lastOwnChangeCount = pasteboard.changeCount
        monitor.lastOwnChangeCount = lastOwnChangeCount
        return true
    }

    private static func postPaste() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
