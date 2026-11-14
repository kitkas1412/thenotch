//
//  NotchPane.swift
//  thenotch
//

import SwiftUI

/// The Notch tool: its switch, then one section per module (its switch, and
/// what it needs or offers right under it, only while it's on). While the
/// tool is off the island isn't running, so the modules are hidden and
/// can't be changed (turning one off must remove its hooks, which only
/// happens while the island runs).
struct NotchPane: View {
    var settings: AppSettings

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var isBluetoothDenied = BluetoothPermission.isDenied

    private var isToolOn: Bool { settings.isToolEnabled(.notch) }

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    symbol: ToolKind.notch.symbol,
                    tint: ToolKind.notch.tint,
                    title: ToolKind.notch.title,
                    summary: ToolKind.notch.summary,
                    isOn: Binding(
                        get: { isToolOn },
                        set: { settings.setToolEnabled(.notch, $0) }
                    )
                )
                if !isToolOn {
                    SettingsNote("Turning Notch off hides the island and stops its modules. Turn it on to choose what it shows.")
                }
            }

            if isToolOn {
                ForEach(ModuleKind.allCases) { kind in
                    Section {
                        SettingsToggleRow(
                            symbol: kind.symbol,
                            tint: kind.tint,
                            title: kind.title,
                            summary: kind.summary,
                            isOn: Binding(
                                get: { settings.isEnabled(kind) },
                                set: { enabled in
                                    settings.setEnabled(kind, enabled)
                                    // Ask in context, when the module is turned on.
                                    if kind.needsAccessibility && enabled {
                                        AccessibilityPermission.request()
                                    }
                                }
                            )
                        )
                        if settings.isEnabled(kind) {
                            details(for: kind)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .onAppear(perform: refreshPermissions)
        // Back from System Settings, or a permission prompt answered.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: AccessibilityPermission.didChangeNotification)) { _ in
            // The change applies a moment after the notification.
            Task {
                try? await Task.sleep(for: .seconds(1))
                refreshPermissions()
            }
        }
    }

    @ViewBuilder
    private func details(for kind: ModuleKind) -> some View {
        switch kind {
        case .shelf:
            Picker("Keep files for", selection: Binding(
                get: { settings.shelfLifetime },
                set: { settings.shelfLifetime = $0 }
            )) {
                ForEach(ShelfLifetime.allCases) { lifetime in
                    Text(lifetime.title).tag(lifetime)
                }
            }
            SettingsNote("Files from Finder stay where they are; the shelf only points to them. Images and other content dragged from apps are saved by \(AppIdentity.name) and deleted when they leave the shelf.")
        case .hud:
            if !isAccessibilityTrusted {
                SettingsNotice(
                    "Needs Accessibility access to take the volume and brightness keys. Until then, macOS shows its own overlay.",
                    kind: .actionNeeded,
                    action: ("Open Privacy & Security…", { AccessibilityPermission.openSettings() })
                )
            }
        case .notifications:
            if !isAccessibilityTrusted {
                SettingsNotice(
                    "Needs Accessibility access to read the banners. Until then, macOS shows its own.",
                    kind: .actionNeeded,
                    action: ("Open Privacy & Security…", { AccessibilityPermission.openSettings() })
                )
            }
            SettingsNote("Shows only what the banner would: with Show previews off in System Settings › Notifications, the text stays hidden. Notifications stay in Notification Center, and persistent banners are left to macOS, except incoming calls, which you can accept or decline from the island. Nothing is saved or sent.")
        case .bluetooth:
            if isBluetoothDenied {
                SettingsNotice(
                    "Needs Bluetooth access to see devices connect.",
                    kind: .actionNeeded,
                    action: ("Open Privacy & Security…", { BluetoothPermission.openSettings() })
                )
            }
        case .claudeCode:
            if let problem = ClaudeCodeStatus.shared.problem {
                SettingsNotice(problem, kind: .problem)
            } else {
                SettingsNotice(
                    "Hooks added to ~/.claude/settings.json and, if Codex is installed, ~/.codex/hooks.json; they're removed when you turn this off. Prompts and replies aren't read.",
                    kind: .ok,
                    action: ("Show in Finder", {
                        NSWorkspace.shared.activateFileViewerSelecting([ClaudeHooksConfig.settingsURL])
                    })
                )
            }
            if let problem = ClaudeCodeStatus.shared.codexProblem {
                SettingsNotice(problem, kind: .problem)
            }
            SettingsNote("Codex asks you to trust new hooks once: /hooks in the Codex CLI, or Settings › Hooks in the ChatGPT app. If you install Codex later, turn this off and on again.")
        case .nowPlaying, .battery:
            EmptyView()
        }
    }

    private func refreshPermissions() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
        isBluetoothDenied = BluetoothPermission.isDenied
    }
}
