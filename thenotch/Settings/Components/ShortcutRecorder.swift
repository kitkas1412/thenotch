//
//  ShortcutRecorder.swift
//  thenotch
//

import AppKit
import SwiftUI

/// What a captured key press means to the recorder. Pure, so it's testable.
enum ShortcutCapture: Equatable {
    case cancel
    case clear
    case candidate(Shortcut)

    static let escapeKeyCode: UInt16 = 53
    static let deleteKeyCode: UInt16 = 51
    static let forwardDeleteKeyCode: UInt16 = 117

    static func interpret(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> ShortcutCapture {
        let modifiers = Shortcut.Modifiers(flags)
        if modifiers.isEmpty {
            if keyCode == escapeKeyCode { return .cancel }
            if keyCode == deleteKeyCode || keyCode == forwardDeleteKeyCode { return .clear }
        }
        return .candidate(Shortcut(keyCode: keyCode, flags: flags))
    }

    /// The message for a shortcut that can't be saved, or nil if it can.
    @MainActor
    static func problem(for shortcut: Shortcut, actionID: String, hotKeys: HotKeyCenter) -> String? {
        switch shortcut.validation {
        case .needsCommandOrControl:
            return "Use ⌘ or ⌃ with the key"
        case .reservedBySystem(let name):
            return "Used by macOS (\(name))"
        case .valid:
            break
        }
        if let other = hotKeys.conflictingID(for: shortcut, excluding: actionID) {
            let title = ShortcutAction.all.first { $0.id == other }?.title ?? "another shortcut"
            return "Already used by \(title)"
        }
        return nil
    }
}

/// Lets a one-shot event monitor remove itself.
private final class MonitorToken {
    var monitor: Any?
}

/// Owns the key monitors while a recorder captures. Every end path goes
/// through `stop()`, which is idempotent, so suspend/resume stay balanced.
@MainActor
@Observable
final class ShortcutRecordingSession {
    private(set) var isRecording = false

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var releaseMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// A click that ended recording must not start it again through the
    /// button. A button acts on mouse-up, so the flag lasts until that click's
    /// release has been handled.
    @ObservationIgnored private var clickEndedRecording = false

    @ObservationIgnored private var hotKeys: HotKeyCenter?
    @ObservationIgnored private var onCapture: ((ShortcutCapture) -> Void)?

    func start(hotKeys: HotKeyCenter, onCapture: @escaping (ShortcutCapture) -> Void) {
        guard !isRecording else { return }
        if clickEndedRecording {
            clickEndedRecording = false
            return
        }
        isRecording = true
        self.hotKeys = hotKeys
        self.onCapture = onCapture
        hotKeys.suspend()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let isRepeat = event.isARepeat
            // The monitor runs on the main thread. A key is always consumed
            // while recording, so it never reaches the window.
            MainActor.assumeIsolated { self.handle(keyCode: keyCode, flags: flags, isRepeat: isRepeat) }
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.isRecording else { return }
                self.clickEndedRecording = true
                // The monitor removes itself on the first release, even if the
                // session is gone by then, so it can't outlive that click.
                let token = MonitorToken()
                token.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
                    if let monitor = token.monitor { NSEvent.removeMonitor(monitor) }
                    token.monitor = nil
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.endClick() }
                    }
                    return event
                }
                self.releaseMonitor = token.monitor
                self.stop()
            }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
    }

    private func endClick() {
        clickEndedRecording = false
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        onCapture = nil
        hotKeys?.resume()
        hotKeys = nil
    }

    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool) {
        guard isRecording, !isRepeat else { return }
        onCapture?(ShortcutCapture.interpret(keyCode: keyCode, flags: flags))
    }
}

/// A field that records a global shortcut for `actionID`: click (or Space /
/// Return with Full Keyboard Access) to record, Esc cancels, Delete clears.
/// Rejected shortcuts aren't saved; the reason goes to `problem`.
struct ShortcutRecorder: View {
    let actionID: String
    var settings: AppSettings
    var hotKeys: HotKeyCenter
    @Binding var problem: String?

    @State private var session = ShortcutRecordingSession()

    private var shortcut: Shortcut? { settings.shortcut(for: actionID) }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(label)
                    .foregroundStyle(session.isRecording || shortcut == nil ? .secondary : .primary)
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(session.isRecording ? .accentColor : nil)
            .accessibilityLabel("Shortcut")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(session.isRecording ? "Press the new shortcut, or Escape to cancel" : "Starts recording a shortcut")

            if shortcut != nil, !session.isRecording {
                Button {
                    problem = nil
                    settings.setShortcut(nil, for: actionID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear shortcut")
                .help("Clear shortcut")
            }
        }
        .onDisappear { session.stop() }
    }

    private var label: String {
        if session.isRecording { return "Type shortcut…" }
        return shortcut?.displayString ?? "Record Shortcut"
    }

    private var accessibilityValue: String {
        if session.isRecording { return "Recording" }
        return shortcut?.displayString ?? "Not set"
    }

    private func toggle() {
        if session.isRecording {
            session.stop()
        } else {
            problem = nil
            session.start(hotKeys: hotKeys) { capture in finish(capture) }
        }
    }

    private func finish(_ capture: ShortcutCapture) {
        switch capture {
        case .cancel:
            session.stop()
        case .clear:
            settings.setShortcut(nil, for: actionID)
            session.stop()
        case .candidate(let candidate):
            if let message = ShortcutCapture.problem(for: candidate, actionID: actionID, hotKeys: hotKeys) {
                problem = message
            } else {
                settings.setShortcut(candidate, for: actionID)
            }
            // Resuming registers it with the system and records the result.
            session.stop()
        }
    }
}

/// A settings row: the action's title, its recorder, and under them why a
/// shortcut was refused or isn't working.
struct ShortcutRow: View {
    let action: ShortcutAction
    var settings: AppSettings
    var hotKeys: HotKeyCenter

    @State private var problem: String?

    private var unavailable: Bool {
        settings.shortcut(for: action.id) != nil && hotKeys.lastResult(for: action.id) == .unavailable
    }

    var body: some View {
        LabeledContent(action.title) {
            ShortcutRecorder(actionID: action.id, settings: settings, hotKeys: hotKeys, problem: $problem)
        }
        if let problem {
            SettingsNotice(problem, kind: .problem)
        } else if unavailable {
            SettingsNotice("In use by another app", kind: .problem)
        }
    }
}
