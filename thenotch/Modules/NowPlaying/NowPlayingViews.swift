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
        ArtworkView(service: service, cornerRadius: IslandStyle.Radius.small)
            .frame(width: IslandStyle.Size.compactContent, height: IslandStyle.Size.compactContent)
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
                TimelineView(.periodic(from: .now, by: IslandStyle.levelMeterTick)) { context in
                    bars { Self.height(bar: $0, at: context.date) }
                        .animation(.easeInOut(duration: IslandStyle.levelMeterTick), value: context.date)
                }
            } else {
                // Paused, or Reduce Motion: still bars, taller while playing.
                bars { bar in playing ? [8, 12, 6, 10][bar] : 3 }
            }
        }
        .frame(height: IslandStyle.Size.levelMeter)
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
        let tick = Int(date.timeIntervalSinceReferenceDate / IslandStyle.levelMeterTick)
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

    typealias Size = IslandStyle.Size
    typealias Spacing = IslandStyle.Spacing

    /// Exactly the rows below, so the bottom margin is the content margin.
    static let contentHeight = Size.artwork + Spacing.m + Size.labelLine + Spacing.s + Size.playerControl + Spacing.content

    var body: some View {
        if let info = service.info {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: IslandStyle.Spacing.m) {
                    ArtworkView(service: service, cornerRadius: IslandStyle.Radius.large)
                        .frame(width: IslandStyle.Size.artwork, height: IslandStyle.Size.artwork)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: IslandStyle.Spacing.xxs) {
                        Text(info.title)
                            .font(.islandTitle)
                            .foregroundStyle(.primary)
                        Text(info.artist)
                            .font(.islandSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    // Centered beside the artwork.
                    .frame(height: IslandStyle.Size.artwork)
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: IslandStyle.Spacing.s)

                    // Level with the title, top right.
                    LevelMeterView(service: service)
                        .padding(.top, IslandStyle.Spacing.l)
                }
                .padding(.bottom, IslandStyle.Spacing.m)

                ProgressRow(info: info)
                    .padding(.bottom, IslandStyle.Spacing.s)

                HStack(spacing: 0) {
                    if info.source.supportsFavorites {
                        FavoriteButton(isFavorite: info.isFavorite ?? false) {
                            service.toggleFavorite()
                        }
                    } else {
                        // Spotify can't be scripted to favorite a track; an
                        // empty slot keeps the playback controls centered.
                        Color.clear
                            .frame(width: IslandStyle.Size.playerControl, height: IslandStyle.Size.playerControl)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    if service.permissionDenied {
                        Button("Allow thenotch to control \(info.source.scriptName)…") {
                            service.requestPermission()
                        }
                        .buttonStyle(.link)
                        .font(.islandLabel)
                    } else {
                        PlaybackControls(service: service, isPlaying: info.isPlaying)
                    }
                    Spacer()
                    OutputButton(outputs: outputs)
                }
            }
            .islandContentMargins()
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            IslandEmptyState(title: "Nothing playing", message: "Play something in Music or Spotify.")
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
            HStack(spacing: IslandStyle.Spacing.s) {
                Text(known ? Self.format(elapsed) : "")
                    .frame(width: IslandStyle.Size.timeLabel, alignment: .leading)
                IslandProgressBar(fraction: known ? elapsed / duration : 0)
                Text(known ? Self.format(duration) : "")
                    .frame(width: IslandStyle.Size.timeLabel, alignment: .trailing)
            }
            .font(.islandNumeric)
            .frame(height: IslandStyle.Size.labelLine)
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

private struct PlaybackControls: View {
    var service: NowPlayingService
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: IslandStyle.Spacing.xl) {
            control("Previous Track", symbol: "backward.fill", size: .large) { service.previousTrack() }
            control(isPlaying ? "Pause" : "Play", symbol: isPlaying ? "pause.fill" : "play.fill", size: .hero) { service.playPause() }
            control("Next Track", symbol: "forward.fill", size: .large) { service.nextTrack() }
        }
    }

    private func control(_ title: String, symbol: String, size: IslandStyle.SymbolSize, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.islandSymbol(size))
                .frame(width: IslandStyle.Size.playerControl, height: IslandStyle.Size.playerControl)
        }
        .buttonStyle(.islandIcon(isProminent: true))
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
                .font(.islandSymbol(.control))
                .foregroundStyle(isFavorite ? AnyShapeStyle(IslandSignal.favorite) : AnyShapeStyle(.secondary))
                .frame(width: IslandStyle.Size.playerControl, height: IslandStyle.Size.playerControl)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.islandIcon(isFilled: true))
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
                .font(.islandSymbol(.control))
                .frame(width: IslandStyle.Size.playerControl, height: IslandStyle.Size.playerControl)
        }
        // Filled like the favorite star, so both ends of the row show their
        // edge at the margin.
        .buttonStyle(.islandIcon(isFilled: true))
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
