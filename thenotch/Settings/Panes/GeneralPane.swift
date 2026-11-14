//
//  GeneralPane.swift
//  thenotch
//

import ServiceManagement
import SwiftUI

struct GeneralPane: View {
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
                        "Allow \(AppIdentity.name) in Login Items to finish turning this on.",
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
