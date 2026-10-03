//
//  BatteryModule.swift
//  thenotch
//

import SwiftUI

/// Briefly shows the battery ("peek") when the charger is plugged in or
/// unplugged, or the battery runs low.
@MainActor
final class BatteryModule: IslandModule {
    let id = "battery"
    /// Above Now Playing: a peek is short and time-sensitive.
    static let priority = 50
    /// How long a peek stays in the compact island.
    static let peekDuration: TimeInterval = 3

    private let service = BatteryService()
    private let activities: ActivityCenter
    /// What the current peek is about, for its icon.
    private let model = BatteryPeekModel()

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

    private func handleChange(_ status: BatteryStatus?, previous: BatteryStatus?) {
        guard let peek = status?.peek(from: previous) else { return }
        model.peek = peek
        activities.publish(LiveActivity(
            id: id,
            moduleID: id,
            priority: Self.priority,
            expiresAt: .now.addingTimeInterval(Self.peekDuration)
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

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
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
        guard let status = service.status else { return .white }
        if status.isPluggedIn { return .green }
        if case .low = model.peek { return .red }
        return .white
    }
}

private struct BatteryPercentText: View {
    var service: BatteryService

    var body: some View {
        Text(service.status.map { "\($0.percent)%" } ?? "")
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private struct BatteryExpandedView: View {
    var service: BatteryService
    var model: BatteryPeekModel

    var body: some View {
        if let status = service.status {
            HStack(spacing: 16) {
                BatteryIcon(service: service, model: model)
                    .scaleEffect(2)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(status.percent)%")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(Self.detail(status))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

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
