//
//  WindowManagementPane.swift
//  thenotch
//

import SwiftUI

/// The Window Management tool: its switch, the Accessibility access it
/// needs (asked for when it is turned on, not at launch), and its shortcuts
/// grouped by kind.
struct WindowManagementPane: View {
    var settings: AppSettings
    var hotKeys: HotKeyCenter

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted

    private var isToolOn: Bool { settings.isToolEnabled(.windowManagement) }

    private static let groups: [(title: String, actions: [WindowAction])] = [
        ("Halves", [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        ("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Thirds", [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds]),
        ("Other", [.maximize, .center]),
        ("Displays", [.nextDisplay, .previousDisplay]),
    ]

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    symbol: ToolKind.windowManagement.symbol,
                    tint: ToolKind.windowManagement.tint,
                    title: ToolKind.windowManagement.title,
                    summary: ToolKind.windowManagement.summary,
                    isOn: Binding(
                        get: { isToolOn },
                        set: { enabled in
                            settings.setToolEnabled(.windowManagement, enabled)
                            // Ask in context, when the tool is turned on.
                            if enabled && !AccessibilityPermission.isTrusted {
                                AccessibilityPermission.request()
                            }
                        }
                    )
                )
                if !isToolOn {
                    SettingsNote("Turn Window Management on to move and resize the focused window with shortcuts.")
                }
                if isToolOn && !isAccessibilityTrusted {
                    SettingsNotice(
                        "Window Management needs Accessibility access to move other apps' windows.",
                        kind: .actionNeeded,
                        action: ("Open Privacy & Security…", { AccessibilityPermission.openSettings() })
                    )
                }
            }

            if isToolOn {
                ForEach(Self.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.actions) { windowAction in
                            if let action = shortcutAction(for: windowAction) {
                                row(for: action)
                            }
                        }
                    }
                }

                Section {
                    Button("Restore Defaults") {
                        for action in ShortcutAction.actions(for: .windowManagement) {
                            settings.resetShortcut(for: action.id)
                        }
                    }
                    .disabled(ShortcutAction.actions(for: .windowManagement).allSatisfy(isDefault))
                    SettingsNote("macOS 15 and later has its own window tiling: Globe or Fn + Control shortcuts, and dragging a window to an edge (System Settings › Desktop & Dock). They work alongside these; if a shortcut collides, change ours. Full-screen windows aren't moved.")
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .onAppear(perform: refreshPermission)
        // Back from System Settings, or a permission prompt answered.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: AccessibilityPermission.didChangeNotification)) { _ in
            // The change applies a moment after the notification.
            Task {
                try? await Task.sleep(for: .seconds(1))
                refreshPermission()
            }
        }
    }

    private func shortcutAction(for windowAction: WindowAction) -> ShortcutAction? {
        let id = ShortcutAction.windowActionID(windowAction)
        return ShortcutAction.actions(for: .windowManagement).first { $0.id == id }
    }

    private func isDefault(_ action: ShortcutAction) -> Bool {
        settings.shortcut(for: action.id) == action.defaultShortcut
    }

    private func row(for action: ShortcutAction) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                ShortcutRow(action: action, settings: settings, hotKeys: hotKeys)
            }
            // Keeps the recorders aligned whether or not Reset shows.
            Button {
                settings.resetShortcut(for: action.id)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to default")
            .accessibilityLabel("Reset \(action.title) shortcut")
            .opacity(isDefault(action) ? 0 : 1)
            .disabled(isDefault(action))
            .accessibilityHidden(isDefault(action))
        }
    }

    private func refreshPermission() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
    }
}
