//
//  SettingsView.swift
//  thenotch
//

import ServiceManagement
import SwiftUI

/// The settings window: a pane per area, chosen in its toolbar (HIG
/// Settings › macOS). The window takes each pane's title and size, and
/// opens on the pane used last.
struct SettingsView: View {
    var settings: AppSettings
    var updater: Updater

    enum Pane: String {
        case general, modules
    }

    @AppStorage("settings.pane") private var pane = Pane.general

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettingsPane(settings: settings, updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)
            ModulesSettingsPane(settings: settings)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
                .tag(Pane.modules)
        }
        .frame(width: SettingsLayout.width)
    }
}

enum SettingsLayout {
    static let width: CGFloat = 500
    /// Side of a module's icon tile, like the rows of System Settings.
    static let iconTile: CGFloat = 22
}

// MARK: - General

private struct GeneralSettingsPane: View {
    var settings: AppSettings
    var updater: Updater

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if settings.launchAtLoginStatus == .requiresApproval {
                    SettingsNotice(
                        "Allow thenotch in Login Items to finish turning this on.",
                        kind: .actionNeeded,
                        action: ("Open Login Items…", { SMAppService.openSystemSettingsLoginItems() })
                    )
                }
                if let error = settings.launchAtLoginError {
                    SettingsNotice(error, kind: .problem)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent("Version") {
                    HStack(spacing: 12) {
                        Text(Self.version)
                            .textSelection(.enabled)
                        // Opens Sparkle's window: an ellipsis (HIG Buttons).
                        Button("Check for Updates…") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings.refreshLaunchAtLogin()
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - Modules

/// One section per module: its switch, then what it needs (a permission)
/// or offers (the shelf's lifetime) right under it, only while it's on.
private struct ModulesSettingsPane: View {
    var settings: AppSettings

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var isBluetoothDenied = BluetoothPermission.isDenied

    var body: some View {
        Form {
            ForEach(ModuleKind.allCases) { kind in
                Section {
                    ModuleToggle(kind: kind, isOn: Binding(
                        get: { settings.isEnabled(kind) },
                        set: { enabled in
                            settings.setEnabled(kind, enabled)
                            // Ask in context, when the module is turned on.
                            if kind == .hud && enabled {
                                AccessibilityPermission.request()
                            }
                        }
                    ))
                    if settings.isEnabled(kind) {
                        details(for: kind)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
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
            SettingsNote("Files from Finder stay where they are; the shelf only points to them. Images and other content dragged from apps are saved by thenotch and deleted when they leave the shelf.")
        case .hud:
            if !isAccessibilityTrusted {
                SettingsNotice(
                    "Needs Accessibility access to take the volume and brightness keys. Until then, macOS shows its own overlay.",
                    kind: .actionNeeded,
                    action: ("Open Privacy & Security…", { AccessibilityPermission.openSettings() })
                )
            }
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
                    "Hooks added to ~/.claude/settings.json; they're removed when you turn this off. Prompts and replies aren't read.",
                    kind: .ok,
                    action: ("Show in Finder", {
                        NSWorkspace.shared.activateFileViewerSelecting([ClaudeHooksConfig.settingsURL])
                    })
                )
            }
        case .nowPlaying, .battery:
            EmptyView()
        }
    }

    private func refreshPermissions() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
        isBluetoothDenied = BluetoothPermission.isDenied
    }
}

/// A module's switch: its icon tile, name and what it does.
private struct ModuleToggle: View {
    let kind: ModuleKind
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                ModuleIconTile(kind: kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(kind.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // A primary setting: a regular switch over the small controls
        // below it (HIG Toggles › Switches).
        .controlSize(.regular)
    }
}

/// The module's symbol, white on a colored rounded square.
private struct ModuleIconTile: View {
    let kind: ModuleKind

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: SettingsLayout.iconTile, height: SettingsLayout.iconTile)
            .background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

private extension ModuleKind {
    /// The icon tile's color.
    var tint: Color {
        switch self {
        case .nowPlaying: .pink
        case .battery: .green
        case .shelf: .blue
        case .hud: .gray
        case .bluetooth: .indigo
        case .claudeCode: .orange
        }
    }
}

// MARK: - Notices

/// A short explanation under a setting.
private struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A status under a setting, with a symbol so it isn't told by color
/// alone, and the action that resolves it.
private struct SettingsNotice: View {
    enum Kind {
        case ok, actionNeeded, problem

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .actionNeeded: "exclamationmark.triangle.fill"
            case .problem: "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ok: .green
            case .actionNeeded: .yellow
            case .problem: .red
            }
        }
    }

    let text: String
    let kind: Kind
    var action: (title: String, perform: () -> Void)?

    init(_ text: String, kind: Kind, action: (String, () -> Void)? = nil) {
        self.text = text
        self.kind = kind
        self.action = action.map { (title: $0.0, perform: $0.1) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.title, action: action.perform)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
