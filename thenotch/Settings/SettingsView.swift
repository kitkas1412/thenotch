//
//  SettingsView.swift
//  thenotch
//

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var settings: AppSettings
    var updater: Updater

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var isBluetoothDenied = BluetoothPermission.isDenied

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if settings.launchAtLoginStatus == .requiresApproval {
                    HStack {
                        Text("Allow thenotch in Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent("Version \(Self.version)") {
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }

            Section("Modules") {
                ForEach(ModuleKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(kind) },
                        set: { enabled in
                            settings.setEnabled(kind, enabled)
                            // Ask in context, when the module is turned on.
                            if kind == .hud && enabled {
                                AccessibilityPermission.request()
                            }
                        }
                    )) {
                        Text(kind.title)
                        Text(kind.summary)
                    }
                    if kind == .hud && settings.isEnabled(.hud) && !isAccessibilityTrusted {
                        HStack {
                            Text("Allow thenotch in Accessibility to handle the volume and brightness keys. Until then, macOS shows its own overlay.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Accessibility…") {
                                AccessibilityPermission.openSettings()
                            }
                        }
                    }
                    if kind == .claudeCode && settings.isEnabled(.claudeCode) {
                        if let problem = ClaudeCodeStatus.shared.problem {
                            Text(problem)
                                .foregroundStyle(.red)
                        } else {
                            Text("thenotch added hooks to ~/.claude/settings.json (a copy of the original is kept next to it). They tell thenotch when a session starts, works, finishes or asks for permission, and are removed when you turn this off. Prompts and replies aren't read.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if kind == .bluetooth && settings.isEnabled(.bluetooth) && isBluetoothDenied {
                        HStack {
                            Text("Allow thenotch in Bluetooth to see devices connect.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Bluetooth…") {
                                BluetoothPermission.openSettings()
                            }
                        }
                    }
                }
            }

            Section {
                Picker("Keep files for", selection: Binding(
                    get: { settings.shelfLifetime },
                    set: { settings.shelfLifetime = $0 }
                )) {
                    ForEach(ShelfLifetime.allCases) { lifetime in
                        Text(lifetime.title).tag(lifetime)
                    }
                }
                .disabled(!settings.isEnabled(.shelf))
            } header: {
                Text("Shelf")
            } footer: {
                Text("Files from Finder stay where they are; the shelf only points to them. Images and other content dragged from apps are saved by thenotch and deleted when they leave the shelf.")
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings.refreshLaunchAtLogin()
            isAccessibilityTrusted = AccessibilityPermission.isTrusted
            isBluetoothDenied = BluetoothPermission.isDenied
        }
        // Back from System Settings, or a permission prompt answered.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isBluetoothDenied = BluetoothPermission.isDenied
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: AccessibilityPermission.didChangeNotification)) { _ in
            // The change applies a moment after the notification.
            Task {
                try? await Task.sleep(for: .seconds(1))
                isAccessibilityTrusted = AccessibilityPermission.isTrusted
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
