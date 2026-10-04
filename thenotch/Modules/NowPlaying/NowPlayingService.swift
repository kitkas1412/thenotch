//
//  NowPlayingService.swift
//  thenotch
//

import AppKit
import ImageIO
import Observation

/// Tracks what Spotify and Music are playing and controls playback.
///
/// State comes from the apps' distributed notifications, which need no
/// permission. Playback controls and the playback position use AppleScript,
/// which needs Automation permission; if it's denied, the track is still
/// shown and `permissionDenied` tells the UI to offer a "Grant access" button.
@MainActor
@Observable
final class NowPlayingService {
    /// Track to display, if any app is playing or paused.
    private(set) var info: NowPlayingInfo?
    /// Automation was denied for the app owning `info`.
    private(set) var permissionDenied = false
    /// Album artwork of `info`, downscaled; `nil` until loaded or if the
    /// app doesn't provide a URL (Music).
    private(set) var artwork: NSImage?
    /// Accent color from `artwork` (`ArtworkTint`); `nil` for gray artwork
    /// or none.
    private(set) var artworkTint: NSColor?
    /// Icon of the app owning `info`, shown when there's no artwork.
    private(set) var appIcon: NSImage?

    /// Called whenever `info` changes (for publishing live activities).
    @ObservationIgnored var onInfoChange: ((NowPlayingInfo?) -> Void)?

    @ObservationIgnored private var tracks: [NowPlayingInfo.Source: NowPlayingInfo] = [:]
    @ObservationIgnored private var deniedSources: Set<NowPlayingInfo.Source> = []
    /// Apps a script has succeeded on, i.e. Automation is granted.
    @ObservationIgnored private var grantedSources: Set<NowPlayingInfo.Source> = []
    /// Looked up once per app: `NSWorkspace` reads it from disk.
    @ObservationIgnored private var appIcons: [NowPlayingInfo.Source: NSImage] = [:]
    @ObservationIgnored private var artworkCache: [URL: (image: NSImage, tint: NSColor?)] = [:]
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        guard observers.isEmpty else { return }
        observe("com.spotify.client.PlaybackStateChanged") { [weak self] userInfo in
            self?.update(.spotify, NowPlayingInfo.fromSpotify(userInfo, now: .now))
        }
        observe("com.apple.Music.playerInfo") { [weak self] userInfo in
            self?.update(.music, NowPlayingInfo.fromMusic(userInfo, now: .now))
        }

        // Apps don't always post "Stopped" when they quit.
        let workspace = NSWorkspace.shared.notificationCenter
        let token = workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let source = NowPlayingInfo.Source.allCases.first(where: { $0.bundleID == app?.bundleIdentifier }) else { return }
                self?.update(source, nil)
            }
        }
        observers.append((workspace, token))

        // Notifications only arrive on changes, so read what's already
        // playing — but only where permission was granted before, so
        // launching thenotch never triggers a prompt.
        for source in NowPlayingInfo.Source.allCases where MediaAppScripting.isRunning(source) {
            Task {
                let status = await Self.permissionStatus(for: source, prompt: false)
                if status == .granted {
                    await refresh(source)
                }
            }
        }
    }

    func stop() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        tracks.removeAll()
        recompute()
    }

    // MARK: - Controls

    func playPause() { send(.playPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    /// Marks the current track as a favorite, or unmarks it (Music only).
    /// The star updates right away and reverts if Music refuses.
    func toggleFavorite() {
        guard let info, info.source.supportsFavorites else { return }
        let favorite = !(info.isFavorite ?? false)
        setFavorite(favorite, for: info)
        Task {
            let result = await MediaAppScripting.setFavorite(favorite, in: info.source)
            handle(result, for: info.source)
            if case .failure = result {
                setFavorite(!favorite, for: info)
            }
        }
    }

    /// Re-reads the current track (e.g. for an up-to-date playback position
    /// when the island opens). Does nothing without permission.
    func refresh() {
        guard let source = info?.source, !deniedSources.contains(source) else { return }
        Task { await refresh(source) }
    }

    /// Asks for Automation permission for the current app (shows the system
    /// prompt the first time), or opens System Settings if it was denied.
    func requestPermission() {
        guard let source = info?.source else { return }
        if deniedSources.contains(source) {
            AutomationPermission.openSettings()
            return
        }
        Task {
            let status = await Self.permissionStatus(for: source, prompt: true)
            setDenied(source, status == .denied)
            if status == .granted {
                await refresh(source)
            }
        }
    }

    // MARK: - Private

    private func send(_ command: MediaAppScripting.Command) {
        guard let source = info?.source else { return }
        Task {
            let result = await MediaAppScripting.send(command, to: source)
            handle(result, for: source)
        }
    }

    private func refresh(_ source: NowPlayingInfo.Source) async {
        let result = await MediaAppScripting.currentTrack(of: source)
        handle(result, for: source)
        guard case .success(let track?) = result else {
            if case .success(nil) = result { update(source, nil) }
            return
        }
        update(source, track)
        // Read separately: older Music versions name the property `loved`,
        // and a failure here mustn't lose the track itself.
        if source.supportsFavorites,
           case .success(let favorite) = await MediaAppScripting.isFavorite(in: source) {
            setFavorite(favorite, for: track)
        }
    }

    /// Sets the favorite flag of `track` if it's still the current track of
    /// its app.
    private func setFavorite(_ favorite: Bool, for track: NowPlayingInfo) {
        guard var current = tracks[track.source],
              current.title == track.title, current.artist == track.artist,
              current.isFavorite != favorite
        else { return }
        current.isFavorite = favorite
        tracks[track.source] = current
        recompute()
    }

    private func handle<T>(_ result: Result<T, MediaAppScripting.ScriptError>, for source: NowPlayingInfo.Source) {
        switch result {
        case .success:
            grantedSources.insert(source)
            setDenied(source, false)
        case .failure(.permissionDenied):
            setDenied(source, true)
        case .failure(.notRunning):
            update(source, nil)
        case .failure:
            break
        }
    }

    private func update(_ source: NowPlayingInfo.Source, _ track: NowPlayingInfo?) {
        let previous = tracks[source]
        tracks[source] = track?.filledIn(from: previous)
        recompute()

        // Notifications carry no artwork (and Music no position): read
        // them via AppleScript when a new track starts, if allowed.
        if let track, grantedSources.contains(source),
           previous?.title != track.title || previous?.artist != track.artist {
            Task { await refresh(source) }
        }
    }

    private func setDenied(_ source: NowPlayingInfo.Source, _ denied: Bool) {
        if denied {
            deniedSources.insert(source)
        } else {
            deniedSources.remove(source)
        }
        recompute()
    }

    private func recompute() {
        let preferred = NowPlayingInfo.preferred(Array(tracks.values))
        if preferred != info {
            if preferred?.source != info?.source {
                appIcon = preferred.flatMap { icon(of: $0.source) }
            }
            info = preferred
            loadArtwork(for: preferred?.artworkURL)
            onInfoChange?(preferred)
        }
        let denied = preferred.map { deniedSources.contains($0.source) } ?? false
        if denied != permissionDenied {
            permissionDenied = denied
        }
    }

    private func icon(of source: NowPlayingInfo.Source) -> NSImage? {
        if let icon = appIcons[source] {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[source] = icon
        return icon
    }

    /// Side length artwork is downscaled to (2× the largest display size).
    private static let artworkPixelSize: CGFloat = 160

    private func loadArtwork(for url: URL?) {
        guard let url else {
            artworkTask?.cancel()
            artwork = nil
            artworkTint = nil
            return
        }
        if let cached = artworkCache[url] {
            if artwork !== cached.image {
                artwork = cached.image
                artworkTint = cached.tint
            }
            return
        }
        artworkTask?.cancel()
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled else { return }
            // Decoding and scaling block for a while: not on the main thread.
            let side = Self.artworkPixelSize
            let decoded = await Task.detached(priority: .utility) {
                NowPlayingService.thumbnail(from: data, side: side)
            }.value
            guard let (rep, tint) = decoded, !Task.isCancelled else { return }
            let thumbnail = NSImage(size: NSSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2))
            thumbnail.addRepresentation(rep)
            if artworkCache.count >= 50 {
                artworkCache.removeAll()
            }
            artworkCache[url] = (thumbnail, tint)
            if info?.artworkURL == url {
                artwork = thumbnail
                artworkTint = tint
            }
        }
    }

    /// Decodes `data` straight to about `side` pixels (ImageIO, so the
    /// full-size image is never decoded), draws it into a `side`×`side` RGBA
    /// bitmap (shown at @2x) and takes its tint. Runs off the main thread.
    nonisolated private static func thumbnail(from data: Data, side: CGFloat) -> (NSBitmapImageRep, NSColor?)? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        context.cgContext.interpolationQuality = .high
        context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        context.flushGraphics()
        return (rep, ArtworkTint.tint(of: rep))
    }

    private func observe(_ name: String, handler: @escaping ([AnyHashable: Any]) -> Void) {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { notification in
            let userInfo = notification.userInfo ?? [:]
            MainActor.assumeIsolated {
                handler(userInfo)
            }
        }
        observers.append((center, token))
    }

    private static func permissionStatus(for source: NowPlayingInfo.Source, prompt: Bool) async -> AutomationPermission.Status {
        await Task.detached {
            AutomationPermission.status(for: source.bundleID, prompt: prompt)
        }.value
    }
}
