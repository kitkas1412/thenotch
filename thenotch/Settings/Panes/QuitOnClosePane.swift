//
//  QuitOnClosePane.swift
//  thenotch
//

import SwiftUI
import UniformTypeIdentifiers

/// The Quit on Close tool: its switch, the Accessibility access it needs
/// (asked for when it is turned on), which apps it applies to and how long
/// it waits.
struct QuitOnClosePane: View {
    @Bindable var settings: AppSettings

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted

    private var isToolOn: Bool { settings.isToolEnabled(.quitOnClose) }

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    symbol: ToolKind.quitOnClose.symbol,
                    tint: ToolKind.quitOnClose.tint,
                    title: ToolKind.quitOnClose.title,
                    summary: ToolKind.quitOnClose.summary,
                    isOn: Binding(
                        get: { isToolOn },
                        set: { enabled in
                            settings.setToolEnabled(.quitOnClose, enabled)
                            // Ask in context, when the tool is turned on.
                            if enabled && !AccessibilityPermission.isTrusted {
                                AccessibilityPermission.request()
                            }
                        }
                    )
                )
                if !isToolOn {
                    SettingsNote("Turn Quit on Close on to quit an app when you close its last window.")
                }
                if isToolOn && !isAccessibilityTrusted {
                    SettingsNotice(
                        "Quit on Close needs Accessibility access to see when windows close.",
                        kind: .actionNeeded,
                        action: ("Open Privacy & Security…", { AccessibilityPermission.openSettings() })
                    )
                }
            }

            if isToolOn {
                Section {
                    Picker("Applies to", selection: $settings.quitOnCloseMode) {
                        ForEach(QuitOnCloseMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Quit after", selection: $settings.quitOnCloseDelay) {
                        ForEach(AppSettings.quitOnCloseDelays, id: \.self) { Text("\($0) s").tag($0) }
                    }
                }

                Section(settings.quitOnCloseMode == .onlyListed ? "Apps that quit" : "Apps that stay open") {
                    QuitOnCloseApps(settings: settings)
                }

                Section {
                    SettingsNote("An app with unsaved documents still asks to save. Windows on other Spaces or minimized keep the app open. Finder, the Dock and system apps never quit.")
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

    private func refreshPermission() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
    }
}

/// The apps the list names: a list with Remove, and Add….
private struct QuitOnCloseApps: View {
    var settings: AppSettings

    var body: some View {
        if settings.quitOnCloseApps.isEmpty {
            Text("No apps")
                .foregroundStyle(.secondary)
        }
        ForEach(settings.quitOnCloseApps, id: \.self) { bundleID in
            HStack(spacing: 8) {
                Text(Self.name(for: bundleID))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    settings.quitOnCloseApps.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from the list")
                .accessibilityLabel("Remove \(Self.name(for: bundleID)) from the list")
            }
        }
        Button("Add App…", action: addApp)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !settings.quitOnCloseApps.contains(id) else { continue }
            settings.quitOnCloseApps.append(id)
        }
    }

    private static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
    }
}
