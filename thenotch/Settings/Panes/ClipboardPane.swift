//
//  ClipboardPane.swift
//  thenotch
//

import SwiftUI
import UniformTypeIdentifiers

/// The Clipboard tool: its switch, the access it needs, its shortcut, how
/// much it keeps, which apps it ignores, and Clear History.
struct ClipboardPane: View {
    var settings: AppSettings
    var hotKeys: HotKeyCenter

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var confirmsClear = false
    /// What went wrong clearing the saved history while the tool was off.
    @State private var clearProblem: String?

    private var isToolOn: Bool { settings.isToolEnabled(.clipboard) }
    private var tool: ClipboardTool? { isToolOn ? ClipboardTool.current : nil }

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    symbol: ToolKind.clipboard.symbol,
                    tint: ToolKind.clipboard.tint,
                    title: ToolKind.clipboard.title,
                    summary: ToolKind.clipboard.summary,
                    isOn: Binding(
                        get: { isToolOn },
                        set: { enabled in
                            settings.setToolEnabled(.clipboard, enabled)
                            // Ask in context, when pasting needs it.
                            if enabled && settings.clipboardPastesDirectly && !AccessibilityPermission.isTrusted {
                                AccessibilityPermission.request()
                            }
                        }
                    )
                )
                if !isToolOn {
                    SettingsNote("Turn Clipboard on to keep a history of what you copy and paste it back from under the notch.")
                }
                if isToolOn {
                    notices
                }
            }

            if isToolOn {
                Section {
                    ForEach(ShortcutAction.actions(for: .clipboard)) { action in
                        ShortcutRow(action: action, settings: settings, hotKeys: hotKeys)
                    }
                }

                Section("History") {
                    Picker("Keep up to", selection: Binding(
                        get: { settings.clipboardLimit },
                        set: { settings.clipboardLimit = $0 }
                    )) {
                        ForEach(AppSettings.clipboardLimits, id: \.self) { Text("\($0) items").tag($0) }
                    }
                    Toggle("Paste directly into the app", isOn: Binding(
                        get: { settings.clipboardPastesDirectly },
                        set: { enabled in
                            settings.clipboardPastesDirectly = enabled
                            if enabled && !AccessibilityPermission.isTrusted { AccessibilityPermission.request() }
                        }
                    ))
                    Toggle("Include Universal Clipboard", isOn: Binding(
                        get: { settings.clipboardRecordsRemote },
                        set: { settings.clipboardRecordsRemote = $0 }
                    ))
                    Toggle("Clear history when quitting", isOn: Binding(
                        get: { settings.clipboardClearOnQuit },
                        set: { settings.clipboardClearOnQuit = $0 }
                    ))
                }

                Section("Ignored apps") {
                    ClipboardIgnoredApps(settings: settings)
                }
            }

            Section {
                Button("Clear History…", role: .destructive) { confirmsClear = true }
                if let clearProblem {
                    SettingsNotice(clearProblem, kind: .problem)
                }
                SettingsNote("History is encrypted on this Mac. Passwords copied from password managers are skipped.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .alert("Clear clipboard history?", isPresented: $confirmsClear) {
            Button("Clear History", role: .destructive, action: clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything thenotch saved from your clipboard is deleted. This can't be undone.")
        }
        .onAppear(perform: refreshPermission)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: AccessibilityPermission.didChangeNotification)) { _ in
            Task {
                try? await Task.sleep(for: .seconds(1))
                refreshPermission()
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if settings.clipboardPastesDirectly && !isAccessibilityTrusted {
            SettingsNotice(
                "Pasting straight into an app needs Accessibility access. Without it, an item is copied and you press ⌘V yourself.",
                kind: .actionNeeded,
                action: ("Open Privacy & Security…", { AccessibilityPermission.openSettings() })
            )
        }
        if tool?.monitor.privacyBlocked == true {
            SettingsNotice(
                "macOS is blocking clipboard reads — allow thenotch in Privacy & Security › Paste from Other Apps.",
                kind: .actionNeeded
            )
        }
        if let issue = tool?.store.lastStorageIssue {
            SettingsNotice(issue.message, kind: .problem)
        }
    }

    private func clearHistory() {
        clearProblem = nil
        if let tool {
            // A failure shows as the store's issue.
            tool.store.clear()
        } else {
            Task { clearProblem = await ClipboardTool.clearStoredHistory().problem }
        }
    }

    private func refreshPermission() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
    }
}

/// The apps whose copies aren't recorded: a list with Remove, and Add….
private struct ClipboardIgnoredApps: View {
    var settings: AppSettings

    var body: some View {
        if settings.clipboardIgnoredApps.isEmpty {
            Text("No ignored apps")
                .foregroundStyle(.secondary)
        }
        ForEach(settings.clipboardIgnoredApps, id: \.self) { bundleID in
            HStack(spacing: 8) {
                if let icon = ClipboardThumbnails.shared.appIcon(bundleID: bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                }
                Text(Self.name(for: bundleID))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    settings.clipboardIgnoredApps.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop ignoring this app")
                .accessibilityLabel("Stop ignoring \(Self.name(for: bundleID))")
            }
        }
        Button("Add App…", action: addApp)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to ignore"
        panel.prompt = "Ignore"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !settings.clipboardIgnoredApps.contains(id) else { continue }
            settings.clipboardIgnoredApps.append(id)
        }
    }

    private static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
