//
//  MediaAppScripting.swift
//  thenotch
//

import AppKit

/// AppleScript access to Spotify and Music: playback commands and reading
/// the current track. Requires Automation permission.
///
/// Scripts run on a serial background queue because `NSAppleScript` blocks
/// (including while the permission prompt is shown). They only run while
/// the target app is running — `tell application` would launch it, or ask
/// "Where is Spotify?" if it isn't installed.
enum MediaAppScripting {
    enum Command: String {
        case playPause = "playpause"
        case nextTrack = "next track"
        case previousTrack = "previous track"
    }

    enum ScriptError: Error, Equatable {
        case notRunning
        case permissionDenied
        case failed(Int)
    }

    private static let queue = DispatchQueue(label: "me.kitkas1412.thenotch.applescript")

    static func isRunning(_ source: NowPlayingInfo.Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    static func send(_ command: Command, to source: NowPlayingInfo.Source) async -> Result<Void, ScriptError> {
        await run("tell application \"\(source.scriptName)\" to \(command.rawValue)", source: source).map { _ in }
    }

    /// Reads the current track, including the playback position and (for
    /// Spotify) the artwork URL. `.success(nil)` means playback is stopped.
    static func currentTrack(of source: NowPlayingInfo.Source) async -> Result<NowPlayingInfo?, ScriptError> {
        let artwork = source == .spotify ? "artwork url of t" : "\"\""
        let script = """
            tell application "\(source.scriptName)"
                if player state is stopped then return {}
                set t to current track
                return {name of t, artist of t, album of t, player state as string, duration of t, player position, \(artwork)}
            end tell
            """
        return await run(script, source: source).map { parseTrack($0, source: source, now: .now) }
    }

    private static func parseTrack(_ list: NSAppleEventDescriptor, source: NowPlayingInfo.Source, now: Date) -> NowPlayingInfo? {
        guard list.numberOfItems >= 7 else { return nil }
        func string(_ i: Int) -> String { list.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double? {
            list.atIndex(i)?.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue
        }

        // Spotify reports the duration in milliseconds, Music in seconds.
        let duration = number(5).map { source == .spotify ? $0 / 1000 : $0 }
        return NowPlayingInfo(
            source: source,
            title: string(1),
            artist: string(2),
            album: string(3),
            isPlaying: string(4) == "playing",
            duration: duration,
            elapsed: number(6),
            elapsedAt: now,
            artworkURL: URL(string: string(7)).flatMap { $0.scheme == nil ? nil : $0 }
        )
    }

    private static func run(_ source: String, source app: NowPlayingInfo.Source) async -> Result<NSAppleEventDescriptor, ScriptError> {
        guard isRunning(app) else { return .failure(.notRunning) }
        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let result {
                    continuation.resume(returning: .success(result))
                    return
                }
                let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
                switch code {
                case Int(errAEEventNotPermitted): continuation.resume(returning: .failure(.permissionDenied))
                case Int(procNotFound): continuation.resume(returning: .failure(.notRunning))
                default: continuation.resume(returning: .failure(.failed(code)))
                }
            }
        }
    }
}
