//
//  HotKeyCenter.swift
//  thenotch
//

import Carbon.HIToolbox
import Foundation
import Observation

/// Global hotkeys through Carbon's `RegisterEventHotKey`, which needs no
/// permission. Actions register under a string id; one event handler serves
/// them all.
@MainActor
@Observable
final class HotKeyCenter {
    enum RegistrationResult: Equatable, Sendable {
        case registered
        /// `RegisterEventHotKey` refused: usually another app has it.
        case unavailable
        /// `Shortcut.validation` isn't `.valid`.
        case invalid
    }

    private struct Entry {
        var shortcut: Shortcut
        let handler: @MainActor () -> Void
        let numericID: UInt32
        var ref: EventHotKeyRef?
    }

    /// The last outcome per action id, for showing "in use by another app".
    private(set) var results: [String: RegistrationResult] = [:]

    /// While true (a recorder is capturing), no hotkey is active, so the
    /// keys reach the recorder. `register` still remembers them.
    private(set) var isSuspended = false

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var nextNumericID: UInt32 = 1
    @ObservationIgnored private var eventHandler: EventHandlerRef?

    nonisolated private static let signature: OSType = 0x746E_686B // 'tnhk'

    func lastResult(for id: String) -> RegistrationResult? {
        results[id]
    }

    @discardableResult
    func register(
        id: String,
        shortcut: Shortcut,
        handler: @escaping @MainActor () -> Void
    ) -> RegistrationResult {
        unregister(id: id)
        guard shortcut.validation == .valid else {
            results[id] = .invalid
            return .invalid
        }
        var entry = Entry(shortcut: shortcut, handler: handler, numericID: nextNumericID)
        nextNumericID &+= 1
        let result: RegistrationResult
        if isSuspended {
            result = .registered
        } else {
            installHandlerIfNeeded()
            if let ref = registerCarbon(entry) {
                entry.ref = ref
                result = .registered
            } else {
                result = .unavailable
            }
        }
        // An unavailable entry stays booked: `resume()` retries it and
        // `conflictingID` sees it.
        entries[id] = entry
        results[id] = result
        return result
    }

    func unregister(id: String) {
        if let ref = entries.removeValue(forKey: id)?.ref {
            UnregisterEventHotKey(ref)
        }
        results[id] = nil
        removeHandlerIfIdle()
    }

    func unregisterAll() {
        for entry in entries.values {
            if let ref = entry.ref { UnregisterEventHotKey(ref) }
        }
        entries.removeAll()
        results.removeAll()
        removeHandlerIfIdle()
    }

    /// Releases every hotkey while a recorder captures keys. Registrations
    /// are remembered and come back on `resume()`.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for id in entries.keys {
            if let ref = entries[id]?.ref { UnregisterEventHotKey(ref) }
            entries[id]?.ref = nil
        }
    }

    /// `.unavailable` entries are retried only here, on the next `resume()`.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for id in entries.keys.sorted() {
            guard var entry = entries[id] else { continue }
            installHandlerIfNeeded()
            entry.ref = registerCarbon(entry)
            entries[id] = entry
            results[id] = entry.ref == nil ? .unavailable : .registered
        }
    }

    /// The id of another of our actions that already uses `shortcut`.
    func conflictingID(for shortcut: Shortcut, excluding id: String?) -> String? {
        entries.first { $0.key != id && $0.value.shortcut == shortcut }?.key
    }

    deinit {
        for entry in entries.values {
            if let ref = entry.ref { UnregisterEventHotKey(ref) }
        }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    // MARK: Carbon

    private func registerCarbon(_ entry: Entry) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: entry.numericID)
        let status = RegisterEventHotKey(
            entry.shortcut.keyCode,
            entry.shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        return status == noErr ? ref : nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The callback captures nothing: the center comes through userData,
        // unretained (the handler is removed in `deinit`).
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let numericID = hotKeyID.id
                // The application event target delivers on the main thread.
                guard Thread.isMainThread else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    center.fire(numericID)
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr { eventHandler = nil }
    }

    private func removeHandlerIfIdle() {
        guard entries.isEmpty, let handler = eventHandler else { return }
        RemoveEventHandler(handler)
        eventHandler = nil
    }

    private func fire(_ numericID: UInt32) {
        entries.values.first { $0.numericID == numericID }?.handler()
    }
}
