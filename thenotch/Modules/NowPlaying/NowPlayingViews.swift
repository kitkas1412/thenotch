//
//  NowPlayingViews.swift
//  thenotch
//

import SwiftUI

// MARK: - Compact

/// Small artwork in the left wing.
struct CompactArtworkView: View {
    var service: NowPlayingService

    var body: some View {
        ArtworkView(service: service, cornerRadius: 5)
            .frame(width: 20, height: 20)
    }
}

/// Animated bars in the right wing; still while paused.
struct LevelMeterView: View {
    var service: NowPlayingService

    var body: some View {
        let playing = service.info?.isPlaying == true
        // Redraws a few times per second only while playing.
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: playing ? Self.height(bar: bar, at: context.date) : 3)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: context.date)
        }
        .frame(height: 14)
    }

    /// Pseudo-random height in 4...14, stable for a given bar and tick.
    private static func height(bar: Int, at date: Date) -> CGFloat {
        let tick = Int(date.timeIntervalSinceReferenceDate / 0.3)
        let seed = (tick &* 31 &+ bar &* 17) % 11
        return 4 + CGFloat(abs(seed))
    }
}

// MARK: - Expanded

struct NowPlayingExpandedView: View {
    var service: NowPlayingService

    var body: some View {
        if let info = service.info {
            HStack(spacing: 14) {
                ArtworkView(service: service, cornerRadius: 10)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(info.artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))

                    ProgressRow(info: info)

                    if service.permissionDenied {
                        Button("Allow thenotch to control \(info.source.scriptName)…") {
                            service.requestPermission()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else {
                        PlaybackControls(service: service, isPlaying: info.isPlaying)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
        } else {
            Text("Nothing playing")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ProgressRow: View {
    let info: NowPlayingInfo

    var body: some View {
        if let duration = info.duration, duration > 0, info.elapsed != nil {
            // Only ticks while the island is open.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = info.elapsed(at: context.date) ?? 0
                HStack(spacing: 8) {
                    Text(Self.format(elapsed))
                    ProgressView(value: elapsed, total: duration)
                        .progressViewStyle(.linear)
                        .tint(.white)
                    Text(Self.format(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
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
        HStack(spacing: 22) {
            control("backward.fill") { service.previousTrack() }
            control(isPlaying ? "pause.fill" : "play.fill") { service.playPause() }
            control("forward.fill") { service.nextTrack() }
        }
        .padding(.top, 2)
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(.white)
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
