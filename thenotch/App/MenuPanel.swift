//
//  MenuPanel.swift
//  thenotch
//

import AppKit
import SwiftUI

/// The content of the menu bar panel: System Monitor on top while the tool
/// is on, then the app commands as menu-like rows. System styles only.
struct MenuPanel: View {
    let sampler: SystemSampler
    let updater: Updater
    let settings: AppSettings

    @Environment(\.openSettings) private var openSettings
    /// Reference type only: nothing here is mutated while the view updates.
    @State private var panel = PanelWindowTracker()

    static let width: CGFloat = 290

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sampler.isEnabled {
                SystemMonitorSection(sampler: sampler, dismissPanel: panel.dismiss)
                Divider().padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                if settings.isToolEnabled(.clipboard), settings.isToolEnabled(.notch) {
                    MenuRow(
                        title: "Clipboard History…",
                        shortcut: settings.shortcut(for: ShortcutAction.clipboardShowHistory.id)?.displayString
                    ) {
                        panel.dismiss()
                        ClipboardTool.current?.showHistory()
                    }
                    Divider().padding(.vertical, 4)
                }

                MenuRow(title: "Settings…", shortcut: "⌘,") {
                    panel.dismiss()
                    // An agent app isn't frontmost; bring the window forward.
                    NSApp.activate()
                    openSettings()
                }
                .keyboardShortcut(",")

                MenuRow(title: "Check for Updates…") {
                    panel.dismiss()
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)

                MenuRow(title: "Quit \(AppIdentity.name)", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(.vertical, 6)
        .frame(width: Self.width, alignment: .leading)
        // `.onAppear`/`.onDisappear` aren't reliable for a `.window`
        // MenuBarExtra (the content is built once and its NSPanel is ordered
        // in and out), so sampling follows the panel's window instead.
        .background(PanelWindowReader(tracker: panel) { sampler.isPanelVisible = $0 })
    }
}

/// A full-width, menu-like row: hover and keyboard focus use the system
/// selection colors, the shortcut hint sits at the trailing edge.
struct MenuRow: View {
    let title: String
    var symbol: String?
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let symbol {
                    Image(systemName: symbol).imageScale(.small)
                }
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut).opacity(0.65)
                }
            }
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovering = false

        private var isHighlighted: Bool { isEnabled && (isHovering || isFocused || configuration.isPressed) }

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(isHighlighted ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .selectedContentBackgroundColor))
                    }
                }
                .padding(.horizontal, 6)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

/// Follows the MenuBarExtra panel's NSWindow. The window is held weakly.
///
/// Visibility is `isVisible && occlusionState.contains(.visible)`, re-read on
/// key/resign-key, occlusion change and close. Occlusion is the signal that
/// also fires when the panel is ordered out (`orderOut` posts no
/// `willClose`), and `isVisible` guards the moment between the two.
@MainActor
final class PanelWindowTracker {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    fileprivate var onChange: (Bool) -> Void = { _ in }
    private var lastReported: Bool?

    func attach(_ newWindow: NSWindow?) {
        guard newWindow !== window else { return }
        detach()
        window = newWindow
        guard let newWindow else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] note in
                let closing = note.name == NSWindow.willCloseNotification
                MainActor.assumeIsolated { self?.refresh(forceHidden: closing) }
            }
        }
        refresh(forceHidden: false)
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        window = nil
        report(false)
    }

    /// Hides the panel before an action that opens another window or app.
    /// `orderOut` rather than `close`, so the panel can be shown again.
    func dismiss() {
        window?.orderOut(nil)
        report(false)
    }

    private func refresh(forceHidden: Bool) {
        guard !forceHidden, let window else { return report(false) }
        report(window.isVisible && window.occlusionState.contains(.visible))
    }

    private func report(_ visible: Bool) {
        guard visible != lastReported else { return }
        lastReported = visible
        onChange(visible)
    }
}

/// Hands the hosting NSWindow to the tracker once the view has one.
private struct PanelWindowReader: NSViewRepresentable {
    let tracker: PanelWindowTracker
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView()
        view.tracker = tracker
        tracker.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        tracker.onChange = onChange
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? WindowAwareView)?.tracker?.detach()
    }
}

private final class WindowAwareView: NSView {
    var tracker: PanelWindowTracker?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated { tracker?.attach(window) }
    }
}
