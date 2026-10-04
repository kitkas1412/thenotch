//
//  NowPlayingInfo.swift
//  thenotch
//

import Foundation

/// The track a media app is playing (or has paused).
struct NowPlayingInfo: Equatable {
    enum Source: String, CaseIterable {
        case spotify, music

        var bundleID: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }

        /// Whether the app lets other apps mark a track as a favorite.
        /// Spotify's scripting only reads its "starred" flag.
        var supportsFavorites: Bool {
            self == .music
        }

        /// Name used in AppleScript `tell application "…"`.
        var scriptName: String {
            switch self {
            case .spotify: "Spotify"
            case .music: "Music"
            }
        }
    }

    var source: Source
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// Track length in seconds, if known.
    var duration: TimeInterval?
    /// Playback position in seconds at `elapsedAt`, if known.
    var elapsed: TimeInterval?
    var elapsedAt: Date
    var artworkURL: URL?
    /// Favorited in the app; `nil` until read, or if unsupported.
    var isFavorite: Bool?

    /// Playback position at `date`, advancing while playing and clamped to
    /// the track length.
    func elapsed(at date: Date) -> TimeInterval? {
        guard var position = elapsed else { return nil }
        if isPlaying {
            position += date.timeIntervalSince(elapsedAt)
        }
        if let duration {
            position = min(position, duration)
        }
        return max(position, 0)
    }

    /// This track with the playback position moved to `position` (clamped
    /// to the track) at `date`, as when the app seeks.
    func seeking(to position: TimeInterval, at date: Date) -> NowPlayingInfo {
        var seeked = self
        seeked.elapsed = max(0, duration.map { min(position, $0) } ?? position)
        seeked.elapsedAt = date
        return seeked
    }

    /// Fills in what this update lacks (Music notifications carry no
    /// position; neither carries artwork) from the previous state of the
    /// same track.
    func filledIn(from previous: NowPlayingInfo?) -> NowPlayingInfo {
        guard let previous, previous.source == source,
              previous.title == title, previous.artist == artist
        else { return self }
        var merged = self
        if merged.elapsed == nil {
            merged.elapsed = previous.elapsed(at: elapsedAt)
        }
        if merged.artworkURL == nil {
            merged.artworkURL = previous.artworkURL
        }
        if merged.isFavorite == nil {
            merged.isFavorite = previous.isFavorite
        }
        return merged
    }

    /// Track to show when several apps report one: a playing track beats a
    /// paused one, then the most recently updated wins.
    static func preferred(_ candidates: [NowPlayingInfo]) -> NowPlayingInfo? {
        candidates.max { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying {
                return !lhs.isPlaying
            }
            return lhs.elapsedAt < rhs.elapsedAt
        }
    }
}

// MARK: - Parsing

extension NowPlayingInfo {
    /// Parses a `com.spotify.client.PlaybackStateChanged` notification.
    /// Returns `nil` when playback stopped.
    static func fromSpotify(_ userInfo: [AnyHashable: Any], now: Date) -> NowPlayingInfo? {
        guard let state = userInfo["Player State"] as? String, state != "Stopped",
              let title = userInfo["Name"] as? String
        else { return nil }
        return NowPlayingInfo(
            source: .spotify,
            title: title,
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            isPlaying: state == "Playing",
            duration: (userInfo["Duration"] as? NSNumber).map { $0.doubleValue / 1000 },  // ms
            elapsed: (userInfo["Playback Position"] as? NSNumber)?.doubleValue,  // s
            elapsedAt: now
        )
    }

    /// Parses a `com.apple.Music.playerInfo` notification. It carries no
    /// playback position. Returns `nil` when playback stopped.
    static func fromMusic(_ userInfo: [AnyHashable: Any], now: Date) -> NowPlayingInfo? {
        guard let state = userInfo["Player State"] as? String, state != "Stopped",
              let title = userInfo["Name"] as? String
        else { return nil }
        return NowPlayingInfo(
            source: .music,
            title: title,
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            isPlaying: state == "Playing",
            duration: (userInfo["Total Time"] as? NSNumber).map { $0.doubleValue / 1000 },  // ms
            elapsed: nil,
            elapsedAt: now
        )
    }
}
