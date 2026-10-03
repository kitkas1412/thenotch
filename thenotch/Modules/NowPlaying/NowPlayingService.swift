//
//  NowPlayingService.swift
//  thenotch
//

import AppKit
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

    @ObservationIgnored private var tracks: [NowPlayingInfo.Source: NowPlayingInfo] = [:]
    @ObservationIgnored private var deniedSources: Set<NowPlayingInfo.Source> = []
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
        if case .success(let track) = result {
            update(source, track)
        }
    }

    private func handle<T>(_ result: Result<T, MediaAppScripting.ScriptError>, for source: NowPlayingInfo.Source) {
        switch result {
        case .success:
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
        tracks[source] = track?.filledIn(from: tracks[source])
        recompute()
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
            info = preferred
        }
        let denied = preferred.map { deniedSources.contains($0.source) } ?? false
        if denied != permissionDenied {
            permissionDenied = denied
        }
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
