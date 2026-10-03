//
//  BatteryModule.swift
//  thenotch
//

import SwiftUI

/// Briefly shows the battery ("peek") when the charger is plugged in or
/// unplugged, or the battery runs low.
@MainActor
final class BatteryModule: IslandModule {
    let id = ModuleKind.battery.id
    /// Above Now Playing: a peek is short and time-sensitive.
    static let priority = 50
    /// How long a peek stays in the compact island.
    static let peekDuration: TimeInterval = 3

    private let service = BatteryService()
    private let activities: ActivityCenter
    /// What the current peek is about, for its icon.
    private let model = BatteryPeekModel()
    /// End of the current peek, if one is showing.
    private var peekEndsAt: Date?

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        service.onChange = { [weak self] status, previous in
            self?.handleChange(status, previous: previous)
        }
        service.start()
    }

    func stop() {
        service.stop()
        service.onChange = nil
        activities.remove(id: id)
    }

    func compactLeading() -> AnyView {
        AnyView(BatteryIcon(service: service, model: model))
    }

    func compactTrailing() -> AnyView {
        AnyView(BatteryPercentText(service: service))
    }

    func expandedView() -> AnyView {
        AnyView(BatteryExpandedView(service: service, model: model))
    }

    var expandedContentHeight: CGFloat { BatteryExpandedView.contentHeight }

    /// "100%" in the trailing wing (39 pt).
    var compactContentWidth: CGFloat { 40 }

    /// Only during a peek: the battery alone doesn't make the island open.
    var hasExpandedContent: Bool {
        peekEndsAt.map { $0 > .now } ?? false
    }

    private func handleChange(_ status: BatteryStatus?, previous: BatteryStatus?) {
        guard let peek = status?.peek(from: previous) else { return }
        model.peek = peek
        let endsAt = Date.now.addingTimeInterval(Self.peekDuration)
        peekEndsAt = endsAt
        activities.publish(LiveActivity(
            id: id,
            moduleID: id,
            priority: Self.priority,
            expiresAt: endsAt
        ))
    }
}

@MainActor
@Observable
final class BatteryPeekModel {
    var peek: BatteryStatus.Peek?
}

// MARK: - Views

private struct BatteryIcon: View {
    var service: BatteryService
    var model: BatteryPeekModel
    var size: IslandStyle.SymbolSize = .compact

    var body: some View {
        Image(systemName: symbol)
            .font(.islandSymbol(size, weight: .semibold))
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        guard let status = service.status else { return "battery.0percent" }
        if status.isPluggedIn { return "bolt.fill" }
        switch status.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var tint: Color {
        guard let status = service.status else { return .primary }
        if status.isPluggedIn { return IslandSignal.charging }
        if case .low = model.peek { return IslandSignal.critical }
        return .primary
    }
}

private struct BatteryPercentText: View {
    var service: BatteryService

    var body: some View {
        Text(service.status.map { "\($0.percent)%" } ?? "")
            .font(.islandCompact)
            .foregroundStyle(.primary)
    }
}

struct BatteryExpandedView: View {
    var service: BatteryService
    var model: BatteryPeekModel

    var body: some View {
        if let status = service.status {
            HStack(spacing: IslandStyle.Spacing.l) {
                BatteryIcon(service: service, model: model, size: .hero)
                VStack(alignment: .leading, spacing: IslandStyle.Spacing.xxs) {
                    Text("\(status.percent)%")
                        .font(.islandValue)
                        .foregroundStyle(.primary)
                    Text(Self.detail(status))
                        .font(.islandLabel)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Battery")
                .accessibilityValue("\(status.percent)%, \(Self.detail(status))")
                Spacer()
            }
            .frame(height: Self.rowHeight)
            .islandContentMargins()
        }
    }

    /// The percentage (22 pt) over the detail line.
    static let rowHeight: CGFloat = 28 + IslandStyle.Spacing.xxs + IslandStyle.Size.labelLine
    static let contentHeight = rowHeight + IslandStyle.Spacing.content

    static func detail(_ status: BatteryStatus) -> String {
        let remaining = status.minutesRemaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        switch (status.isPluggedIn, status.isCharging) {
        case (true, true):
            return remaining.map { "Charging — \($0) until full" } ?? "Charging"
        case (true, false):
            return status.percent >= 100 ? "Fully charged" : "Plugged in, not charging"
        default:
            return remaining.map { "On battery — \($0) remaining" } ?? "On battery"
        }
    }
}
