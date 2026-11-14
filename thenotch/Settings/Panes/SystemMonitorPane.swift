//
//  SystemMonitorPane.swift
//  thenotch
//

import SwiftUI

/// The System Monitor tool: its switch, then its notes while it is on.
struct SystemMonitorPane: View {
    var settings: AppSettings

    private var isToolOn: Bool { settings.isToolEnabled(.systemMonitor) }

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    symbol: ToolKind.systemMonitor.symbol,
                    tint: ToolKind.systemMonitor.tint,
                    title: ToolKind.systemMonitor.title,
                    summary: ToolKind.systemMonitor.summary,
                    isOn: Binding(
                        get: { isToolOn },
                        set: { settings.setToolEnabled(.systemMonitor, $0) }
                    )
                )
                if !isToolOn {
                    SettingsNote("Turn System Monitor on to see CPU, memory, network and disk at the top of the thenotch menu.")
                }
            }

            if isToolOn {
                Section {
                    SettingsNote("CPU, memory, network and disk show at the top of the thenotch menu.")
                    SettingsNote("Temperatures and fan speeds aren't shown: macOS doesn't offer them without extra privileges.")
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}
