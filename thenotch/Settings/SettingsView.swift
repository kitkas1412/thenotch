//
//  SettingsView.swift
//  thenotch
//

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var settings: AppSettings

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

            Section("Modules") {
                ForEach(ModuleKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(kind) },
                        set: { settings.setEnabled(kind, $0) }
                    )) {
                        Text(kind.title)
                        Text(kind.summary)
                    }
                }
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
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
