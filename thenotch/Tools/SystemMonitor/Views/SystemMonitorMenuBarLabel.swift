//
//  SystemMonitorMenuBarLabel.swift
//  thenotch
//

import AppKit

/// The menu bar text, built as an attributed string for the status item's
/// button: the button then draws it in the menu bar's own color, including
/// when it's highlighted (popover open) or the bar is inactive or in dark
/// mode, which an embedded SwiftUI view doesn't follow reliably.
///
/// Digits are monospaced and values are padded with figure spaces to a fixed
/// width, so the item doesn't resize on every tick.
enum SystemMonitorMenuBarLabel {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let captionFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let figureSpace = "\u{2007}"

    static func title(snapshot: SystemSnapshot, metrics: Set<SystemMetric>) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for metric in SystemMetric.allCases where metrics.contains(metric) {
            if result.length > 0 { result.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            switch metric {
            case .cpu:
                append(result, caption: "CPU", value: percent(snapshot.cpu))
            case .memory:
                append(result, caption: "MEM", value: percent(snapshot.memory.fraction))
            case .network:
                append(result, caption: "↓", value: rate(snapshot.networkDown))
                result.append(NSAttributedString(string: " ", attributes: [.font: font]))
                append(result, caption: "↑", value: rate(snapshot.networkUp))
            }
        }
        return result
    }

    /// Spoken by VoiceOver, e.g. "CPU 12 percent, memory 63 percent".
    static func accessibilityLabel(snapshot: SystemSnapshot, metrics: Set<SystemMetric>) -> String {
        let parts = SystemMetric.allCases.filter(metrics.contains).map { metric -> String in
            switch metric {
            case .cpu: "CPU \(Int((snapshot.cpu * 100).rounded())) percent"
            case .memory: "Memory \(Int((snapshot.memory.fraction * 100).rounded())) percent"
            case .network: "Network download \(MetricFormat.rate(snapshot.networkDown)), upload \(MetricFormat.rate(snapshot.networkUp))"
            }
        }
        return parts.isEmpty ? "System Monitor" : "System Monitor: " + parts.joined(separator: ", ")
    }

    private static func append(_ result: NSMutableAttributedString, caption: String, value: String) {
        result.append(NSAttributedString(string: caption + " ", attributes: [
            .font: captionFont,
            .baselineOffset: 0.5,
        ]))
        result.append(NSAttributedString(string: value, attributes: [.font: font]))
    }

    /// "12%" padded to the width of "100%".
    private static func percent(_ fraction: Double) -> String {
        pad(MetricFormat.percent(fraction), to: 4)
    }

    /// "1.2 MB/s" padded to the width of "999.9 KB/s".
    private static func rate(_ bytesPerSecond: Double) -> String {
        pad(MetricFormat.rate(bytesPerSecond), to: 10)
    }

    private static func pad(_ text: String, to length: Int) -> String {
        String(repeating: figureSpace, count: max(0, length - text.count)) + text
    }
}
