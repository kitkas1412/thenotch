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
