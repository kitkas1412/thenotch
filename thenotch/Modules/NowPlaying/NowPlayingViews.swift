//
//  NowPlayingViews.swift
//  thenotch
//

import CoreAudio
import SwiftUI

// MARK: - Compact

/// Small artwork in the left wing.
struct CompactArtworkView: View {
    var service: NowPlayingService

    var body: some View {
        ArtworkView(service: service, cornerRadius: 5)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

/// Animated bars in the right wing; still while paused.
struct LevelMeterView: View {
    var service: NowPlayingService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let playing = service.info?.isPlaying == true
        Group {
            if playing && !reduceMotion {
                // Redraws a few times per second only while playing.
                TimelineView(.periodic(from: .now, by: 0.3)) { context in
                    bars { Self.height(bar: $0, at: context.date) }
                        .animation(.easeInOut(duration: 0.3), value: context.date)
                }
            } else {
                // Paused, or Reduce Motion: still bars, taller while playing.
                bars { bar in playing ? [8, 12, 6, 10][bar] : 3 }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// The artwork's color, so the meter echoes the music; white without one.
    private var tint: AnyShapeStyle {
        service.artworkTint.map { AnyShapeStyle(Color(nsColor: $0)) } ?? AnyShapeStyle(.primary)
    }

    private func bars(height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { bar in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: height(bar))
            }
        }
    }

    /// Pseudo-random height in 4...14, stable for a given bar and tick.
    private static func height(bar: Int, at date: Date) -> CGFloat {
        let tick = Int(date.timeIntervalSinceReferenceDate / 0.3)
        let seed = (tick &* 31 &+ bar &* 17) % 11
        return 4 + CGFloat(abs(seed))
    }
}

// MARK: - Expanded

/// The open player: artwork and track on top, then progress, then
/// controls, with the app on the left and the audio output on the right.
struct NowPlayingExpandedView: View {
    var service: NowPlayingService
    var outputs: AudioOutputs

    var body: some View {
        if let info = service.info {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(service: service, cornerRadius: 14)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(info.artist)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .padding(.top, 10)
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 8)

                    LevelMeterView(service: service)
                        .padding(.top, 14)
                }
                .padding(.bottom, 14)

                ProgressRow(info: info)
                    .padding(.bottom, 8)

                HStack(spacing: 0) {
                    if info.source.supportsFavorites {
                        FavoriteButton(isFavorite: info.isFavorite ?? false) {
                            service.toggleFavorite()
                        }
                    } else {
                        // Spotify can't be scripted to favorite a track; an
                        // empty slot keeps the playback controls centered.
                        Color.clear
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    if service.permissionDenied {
                        Button("Allow thenotch to control \(info.source.scriptName)…") {
                            service.requestPermission()
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    } else {
                        PlaybackControls(service: service, isPlaying: info.isPlaying)
                    }
                    Spacer()
                    OutputButton(outputs: outputs)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            // Invite the next step instead of a bare status.
            VStack(spacing: 4) {
                Text("Nothing playing")
                    .font(.headline)
                Text("Play something in Music or Spotify.")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProgressRow: View {
    let info: NowPlayingInfo

    var body: some View {
        // Always laid out, so the controls don't jump when a track has no
        // known position (shown as an empty bar without times).
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = info.duration ?? 0
            let elapsed = min(info.elapsed(at: context.date) ?? 0, duration)
            let known = duration > 0 && info.elapsed != nil
            HStack(spacing: 10) {
                Text(known ? Self.format(elapsed) : "")
                    .frame(width: 34, alignment: .leading)
                ProgressBar(fraction: known ? elapsed / duration : 0)
                Text(known ? Self.format(duration) : "")
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.callout.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue(known ? "\(Self.format(elapsed)) of \(Self.format(duration))" : "Unknown")
        }
    }

    /// `m:ss`
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Thick rounded track with the played part filled.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(width: geometry.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: 6)
    }
}

private struct PlaybackControls: View {
    var service: NowPlayingService
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 22) {
            control("Previous Track", symbol: "backward.fill", size: 22) { service.previousTrack() }
            control(isPlaying ? "Pause" : "Play", symbol: isPlaying ? "pause.fill" : "play.fill", size: 30) { service.playPause() }
            control("Next Track", symbol: "forward.fill", size: 22) { service.nextTrack() }
        }
    }

    private func control(_ title: String, symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: size))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(IslandIconButtonStyle(isProminent: true))
        .help(title)
    }
}

/// Star in a filled circle: marks the track as a favorite in Music.
private struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: "star.fill")
                .font(.system(size: 17))
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .frame(width: 36, height: 36)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IslandIconButtonStyle(isFilled: true))
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }
}

/// The current audio output; click to pick another one.
private struct OutputButton: View {
    var outputs: AudioOutputs

    var body: some View {
        Button {
            OutputMenu.show(outputs)
        } label: {
            Label("Audio Output", systemImage: outputs.current?.symbol ?? "hifispeaker")
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(IslandIconButtonStyle())
        .help(outputs.current.map { "Playing on \($0.name)" } ?? "Audio Output")
        .accessibilityValue(outputs.current?.name ?? "")
    }
}

/// Pop-up menu of audio outputs at the pointer, checked on the current one.
@MainActor
private enum OutputMenu {
    /// Menu items' target; kept alive while the menu is up.
    private static var target: Target?

    static func show(_ outputs: AudioOutputs) {
        outputs.refresh()
        let target = Target(outputs: outputs)
        self.target = target
        let menu = NSMenu()
        let header = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for device in outputs.devices {
            let item = NSMenuItem(title: device.name, action: #selector(Target.select(_:)), keyEquivalent: "")
            item.target = target
            item.tag = Int(device.id)
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == outputs.currentID ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class Target: NSObject {
        let outputs: AudioOutputs

        init(outputs: AudioOutputs) {
            self.outputs = outputs
        }

        @objc func select(_ item: NSMenuItem) {
            MainActor.assumeIsolated {
                outputs.select(AudioDeviceID(item.tag))
            }
        }
    }
}

// MARK: - Shared

/// Album artwork, or the playing app's icon when there is none.
struct ArtworkView: View {
    var service: NowPlayingService
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork = service.artwork {
                Image(nsImage: artwork)
                    .resizable()
            } else if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.primary)
            }
        }
        .aspectRatio(contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var appIcon: NSImage? {
        guard let bundleID = service.info?.source.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
