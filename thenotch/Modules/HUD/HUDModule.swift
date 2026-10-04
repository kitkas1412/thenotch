//
//  HUDModule.swift
//  thenotch
//

import AppKit
import CoreAudio
import os
import SwiftUI

/// Replaces the macOS volume and brightness overlay: the keys are handled
/// here (`MediaKeyTap`) and the level shows beside the notch for a moment.
/// Needs Accessibility permission; without it the keys are left to macOS.
/// Keys whose level can't be set here (an output without volume control,
/// no built-in display) are left to macOS too.
@MainActor
final class HUDModule: IslandModule {
    let id = ModuleKind.hud.id
    /// Above the battery: it answers a key just pressed.
    static let priority = 60
    /// How long the level stays after the last press.
    static let duration: TimeInterval = 1.5

    private let activities: ActivityCenter
    private let tap = MediaKeyTap()
    private let model = HUDModel()
    private var accessObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        tap.onPress = { [weak self] press, flags in
            self?.handle(press, flags: flags) ?? false
        }
        startTap()
        // Access granted (or revoked) in System Settings while running.
        accessObserver = DistributedNotificationCenter.default().addObserver(
            forName: AccessibilityPermission.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.accessChanged()
            }
        }
    }

    func stop() {
        if let accessObserver {
            DistributedNotificationCenter.default().removeObserver(accessObserver)
        }
        accessObserver = nil
        retryTask?.cancel()
        retryTask = nil
        tap.stop()
        tap.onPress = nil
        activities.remove(id: id)
    }

    func compactLeading() -> AnyView {
        AnyView(HUDSymbol(model: model))
    }

    func compactTrailing() -> AnyView {
        AnyView(HUDLevelBar(model: model))
    }

    func expandedView() -> AnyView {
        AnyView(EmptyView())
    }

    /// Nothing to open: the level only shows beside the notch.
    var hasExpandedContent: Bool { false }

    var compactContentWidth: CGFloat { IslandStyle.Size.hudLevel }

    // MARK: - Keys

    /// Acts on a key; returns whether it was handled (and so kept from
    /// macOS). Both the press and the release of a handled key are kept.
    private func handle(_ press: MediaKey.Press, flags: CGEventFlags) -> Bool {
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        // Option alone opens Sound or Displays settings: macOS does that.
        if option && !shift { return false }
        let fine = option && shift

        switch press.key {
        case .volumeUp, .volumeDown, .mute:
            guard let device = SystemVolume.defaultOutput(), SystemVolume.canSetVolume(of: device) else { return false }
            if press.key == .mute && !SystemVolume.canMute(device) { return false }
            if press.isDown {
                changeVolume(press.key, of: device, fine: fine)
            }
            return true
        case .brightnessUp, .brightnessDown:
            guard let display = DisplayBrightness.builtInDisplay,
                  let brightness = DisplayBrightness.brightness(of: display)
            else { return false }
            if press.isDown {
                let level = MediaKey.step(brightness, up: press.key == .brightnessUp, fine: fine)
                _ = DisplayBrightness.setBrightness(level, of: display)
                show(.brightness, level: level, isMuted: false)
            }
            return true
        }
    }

    /// Like macOS: Mute toggles; volume keys also unmute.
    private func changeVolume(_ key: MediaKey, of device: AudioDeviceID, fine: Bool) {
        let volume = SystemVolume.volume(of: device) ?? 0
        var muted = SystemVolume.isMuted(device) ?? false
        var level = volume
        if key == .mute {
            muted.toggle()
            _ = SystemVolume.setMuted(muted, of: device)
        } else {
            level = MediaKey.step(volume, up: key == .volumeUp, fine: fine)
            _ = SystemVolume.setVolume(level, of: device)
            if muted {
                muted = false
                _ = SystemVolume.setMuted(false, of: device)
            }
        }
        show(.volume, level: level, isMuted: muted)
    }

    private func show(_ kind: HUDModel.Kind, level: Float, isMuted: Bool) {
        model.kind = kind
        model.level = Double(level)
        model.isMuted = isMuted
        activities.publish(LiveActivity(
            id: id,
            moduleID: id,
            priority: Self.priority,
            expiresAt: .now.addingTimeInterval(Self.duration)
        ))
    }

    // MARK: - Access

    private func startTap() {
        guard !tap.isRunning else { return }
        if !tap.start() {
            Log.hud.notice("No Accessibility access: volume and brightness keys are left to macOS")
        }
    }

    /// The notification comes before the new access applies: try again
    /// shortly after.
    private func accessChanged() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            if !AccessibilityPermission.isTrusted {
                self.tap.stop()
            }
            self.startTap()
        }
    }
}

@MainActor
@Observable
final class HUDModel {
    enum Kind {
        case volume, brightness
    }

    var kind = Kind.volume
    /// 0…1.
    var level: Double = 0
    var isMuted = false

    var symbol: String {
        switch kind {
        case .volume:
            if isMuted || level == 0 { return "speaker.slash.fill" }
            if level < 1 / 3 { return "speaker.wave.1.fill" }
            if level < 2 / 3 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }

    /// The bar is empty while muted, like the macOS overlay.
    var shownLevel: Double {
        kind == .volume && isMuted ? 0 : level
    }
}

// MARK: - Views

/// Left wing: what's changing, next to the notch.
private struct HUDSymbol: View {
    var model: HUDModel

    var body: some View {
        Image(systemName: model.symbol)
            .font(.islandSymbol(.compact, weight: .semibold))
            .foregroundStyle(.primary)
            // Symbols differ in width; keep it still next to the notch.
            .frame(width: IslandStyle.Size.compactContent, height: IslandStyle.Size.compactContent)
            .accessibilityHidden(true)
    }
}

/// Right wing: the level.
private struct HUDLevelBar: View {
    var model: HUDModel

    var body: some View {
        IslandProgressBar(fraction: model.shownLevel, isHighlighted: true)
            .accessibilityElement()
            .accessibilityLabel(model.kind == .volume ? "Volume" : "Brightness")
            .accessibilityValue(model.kind == .volume && model.isMuted
                ? "Muted"
                : "\(Int((model.level * 100).rounded()))%")
    }
}
