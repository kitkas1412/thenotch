//
//  SystemMonitorSection.swift
//  thenotch
//

import SwiftUI

/// The System Monitor block at the top of the menu panel: one block per
/// metric, then Activity Monitor. System styles only; it follows the menu
/// bar's appearance. Until the first reading arrives it shows placeholders
/// instead of zeros.
struct SystemMonitorSection: View {
    let sampler: SystemSampler
    /// Closes the panel; run before an action that opens another app.
    var dismissPanel: () -> Void = {}

    private static let placeholder = "—"

    var body: some View {
        let snapshot = sampler.snapshot
        let hasReading = snapshot != SystemSnapshot()
        VStack(alignment: .leading, spacing: 12) {
            MetricBlock(
                title: "CPU",
                value: hasReading ? MetricFormat.percent(snapshot.cpu) : Self.placeholder,
                fraction: hasReading ? snapshot.cpu : nil,
                spoken: hasReading ? percentWords(snapshot.cpu) : "No reading yet"
            )
            MetricBlock(
                title: "Memory",
                value: hasReading
                    ? "\(MetricFormat.capacity(snapshot.memory.used)) of \(MetricFormat.capacity(snapshot.memory.total))"
                    : Self.placeholder,
                fraction: hasReading ? snapshot.memory.fraction : nil,
                spoken: hasReading
                    ? "\(MetricFormat.capacity(snapshot.memory.used)) of \(MetricFormat.capacity(snapshot.memory.total)) used, \(percentWords(snapshot.memory.fraction))"
                    : "No reading yet"
            )
            networkBlock(snapshot, hasReading: hasReading)
            MetricBlock(
                title: "Disk",
                value: hasReading
                    ? "\(MetricFormat.capacity(snapshot.disk.available)) free of \(MetricFormat.capacity(snapshot.disk.total))"
                    : Self.placeholder,
                fraction: hasReading ? snapshot.disk.fraction : nil,
                spoken: hasReading
                    ? "\(MetricFormat.capacity(snapshot.disk.available)) available of \(MetricFormat.capacity(snapshot.disk.total)), \(percentWords(snapshot.disk.fraction)) used"
                    : "No reading yet"
            )
        }
        .monospacedDigit()
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        MenuRow(title: "Open Activity Monitor", symbol: "waveform.path.ecg") {
            dismissPanel()
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func networkBlock(_ snapshot: SystemSnapshot, hasReading: Bool) -> some View {
        let down = hasReading ? MetricFormat.rate(snapshot.networkDown) : Self.placeholder
        let up = hasReading ? MetricFormat.rate(snapshot.networkUp) : Self.placeholder
        return VStack(alignment: .leading, spacing: 4) {
            Text("Network").font(.subheadline.weight(.semibold))
            HStack {
                Label(down, systemImage: "arrow.down")
                Spacer()
                Label(up, systemImage: "arrow.up")
            }
            .font(.callout)
            .labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network")
        .accessibilityValue(hasReading ? "Download \(down), upload \(up)" : "No reading yet")
    }

    private func percentWords(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded())) percent"
    }
}

/// A title with its value, and a thin bar (empty while there is no reading).
private struct MetricBlock: View {
    let title: String
    let value: String
    let fraction: Double?
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(value).font(.callout)
            }
            ProgressView(value: min(1, max(0, fraction ?? 0)))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .opacity(fraction == nil ? 0.4 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
    }
}
