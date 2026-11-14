//
//  SystemMonitorPopoverView.swift
//  thenotch
//

import SwiftUI

/// The popover: one block per metric, then Activity Monitor and Settings.
/// System styles only; it follows the menu bar's appearance.
struct SystemMonitorPopoverView: View {
    let sampler: SystemSampler

    @Environment(\.openSettings) private var openSettings
    @AppStorage("settings.pane") private var storedPane = SettingsPane.general.storedValue

    static let width: CGFloat = 300

    var body: some View {
        let snapshot = sampler.snapshot
        VStack(alignment: .leading, spacing: 14) {
            MetricBlock(
                title: "CPU",
                value: MetricFormat.percent(snapshot.cpu),
                fraction: snapshot.cpu,
                spoken: "\(percentWords(snapshot.cpu))"
            )
            MetricBlock(
                title: "Memory",
                value: "\(MetricFormat.capacity(snapshot.memory.used)) of \(MetricFormat.capacity(snapshot.memory.total))",
                fraction: snapshot.memory.fraction,
                spoken: "\(MetricFormat.capacity(snapshot.memory.used)) of \(MetricFormat.capacity(snapshot.memory.total)) used, \(percentWords(snapshot.memory.fraction))"
            )
            networkBlock(snapshot)
            MetricBlock(
                title: "Disk",
                value: "\(MetricFormat.capacity(snapshot.disk.available)) free of \(MetricFormat.capacity(snapshot.disk.total))",
                fraction: snapshot.disk.fraction,
                spoken: "\(MetricFormat.capacity(snapshot.disk.available)) available of \(MetricFormat.capacity(snapshot.disk.total)), \(percentWords(snapshot.disk.fraction)) used"
            )
            if let battery = snapshot.battery {
                MetricBlock(
                    title: "Battery",
                    value: "\(battery.percent)%",
                    detail: batteryState(battery),
                    fraction: Double(battery.percent) / 100,
                    spoken: "\(battery.percent) percent, \(batteryState(battery))"
                )
            }

            Divider()

            HStack {
                Button("Open Activity Monitor", action: openActivityMonitor)
                Spacer()
                Button("Settings…", action: showSettings)
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
        .monospacedDigit()
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
    }

    private func networkBlock(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Network").font(.subheadline.weight(.semibold))
            HStack {
                Label(MetricFormat.rate(snapshot.networkDown), systemImage: "arrow.down")
                Spacer()
                Label(MetricFormat.rate(snapshot.networkUp), systemImage: "arrow.up")
            }
            .font(.callout)
            .labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network")
        .accessibilityValue("Download \(MetricFormat.rate(snapshot.networkDown)), upload \(MetricFormat.rate(snapshot.networkUp))")
    }

    private func percentWords(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded())) percent"
    }

    private func batteryState(_ battery: BatteryStatus) -> String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return "Plugged in" }
        return "On battery"
    }

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showSettings() {
        storedPane = SettingsPane.tool(.systemMonitor).storedValue
        // An agent app isn't frontmost; bring the window forward.
        NSApp.activate()
        openSettings()
    }
}

/// A title with its value, and a thin bar.
private struct MetricBlock: View {
    let title: String
    let value: String
    var detail: String?
    let fraction: Double
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Text(value).font(.callout)
            }
            ProgressView(value: min(1, max(0, fraction)))
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
    }
}
