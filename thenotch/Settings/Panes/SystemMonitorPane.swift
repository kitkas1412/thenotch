//
//  SystemMonitorPane.swift
//  thenotch
//

import SwiftUI

/// The System Monitor tool: its switch, then what the menu bar shows and
/// how often it updates, only while the tool is on.
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
                    SettingsNote("Turn System Monitor on to see CPU, memory and network in the menu bar.")
                }
            }

            if isToolOn {
                Section("Menu bar") {
                    ForEach(SystemMetric.allCases) { metric in
                        Toggle(metric.title, isOn: Binding(
                            get: { settings.systemMonitorMetrics.contains(metric) },
                            set: { isOn in
                                if isOn {
                                    settings.systemMonitorMetrics.insert(metric)
                                } else {
                                    settings.systemMonitorMetrics.remove(metric)
                                }
                            }
                        ))
                    }
                    Picker("Update every", selection: Binding(
                        get: { settings.systemMonitorInterval },
                        set: { settings.systemMonitorInterval = $0 }
                    )) {
                        ForEach(SystemMonitorInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    SettingsNote("With none selected, the menu bar shows only the icon. Click it for the details, including disk.")
                }

                Section {
                    SettingsNote("Temperatures and fan speeds aren't shown: macOS doesn't offer them without extra privileges.")
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}
