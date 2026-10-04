//
//  BluetoothModule.swift
//  thenotch
//

import SwiftUI

/// Briefly shows a Bluetooth device ("peek") when it connects: its symbol
/// and battery beside the notch, and its name and every battery (each
/// AirPod and the case) when the island opens.
@MainActor
final class BluetoothModule: IslandModule {
    let id = ModuleKind.bluetooth.id
    /// Like the battery's peek; the most recent of the two wins.
    static let priority = 50
    static let peekDuration: TimeInterval = 4

    private let service = BluetoothService()
    private let activities: ActivityCenter
    private let model = BluetoothPeekModel()
    private var peekEndsAt: Date?

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        service.onConnect = { [weak self] device in
            self?.peek(device)
        }
        service.start()
    }

    func stop() {
        service.stop()
        service.onConnect = nil
        activities.remove(id: id)
    }

    func compactLeading() -> AnyView {
        AnyView(BluetoothSymbol(model: model))
    }

    func compactTrailing() -> AnyView {
        AnyView(BluetoothLevelText(model: model))
    }

    func expandedView() -> AnyView {
        AnyView(BluetoothExpandedView(model: model))
    }

    var expandedContentHeight: CGFloat { BluetoothExpandedView.contentHeight }

    /// "100%" in the trailing wing, like the battery's.
    var compactContentWidth: CGFloat { 40 }

    /// Only during a peek.
    var hasExpandedContent: Bool {
        peekEndsAt.map { $0 > .now } ?? false
    }

    /// A new device starts a peek; its battery arriving a moment later
    /// updates the one showing without making it longer.
    private func peek(_ device: BluetoothDevice) {
        let isUpdate = model.device?.address == device.address && hasExpandedContent
        model.device = device
        guard !isUpdate else { return }
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
final class BluetoothPeekModel {
    var device: BluetoothDevice?
}

// MARK: - Views

private struct BluetoothSymbol: View {
    var model: BluetoothPeekModel
    var size: IslandStyle.SymbolSize = .compact

    var body: some View {
        Image(systemName: model.device?.symbol ?? "wave.3.right")
            .font(.islandSymbol(size, weight: .semibold))
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}

/// The battery, or a check mark when the device doesn't report one.
private struct BluetoothLevelText: View {
    var model: BluetoothPeekModel

    var body: some View {
        if let level = model.device?.battery.headline {
            Text("\(level)%")
                .font(.islandCompact)
                .foregroundStyle(level <= BluetoothDevice.lowLevel ? AnyShapeStyle(IslandSignal.critical) : AnyShapeStyle(.primary))
        } else {
            Image(systemName: "checkmark")
                .font(.islandSymbol(.compact, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

struct BluetoothExpandedView: View {
    var model: BluetoothPeekModel

    /// The name over the detail line, like the battery's.
    static let rowHeight = BatteryExpandedView.rowHeight
    static let contentHeight = rowHeight + IslandStyle.Spacing.content

    var body: some View {
        if let device = model.device {
            HStack(spacing: IslandStyle.Spacing.l) {
                BluetoothSymbol(model: model, size: .hero)
                VStack(alignment: .leading, spacing: IslandStyle.Spacing.xxs) {
                    Text(device.name)
                        .font(.islandTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(device.detail)
                        .font(.islandLabel)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(device.name) connected")
                .accessibilityValue(device.detail)
                Spacer()
            }
            .frame(height: Self.rowHeight)
            .islandContentMargins()
        }
    }
}
