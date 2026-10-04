//
//  ClaudeHooksConfig.swift
//  thenotch
//

import Foundation

/// Adds thenotch's hooks to Claude Code's user settings
/// (`~/.claude/settings.json`), and removes them. User-level hooks run for
/// every session: the terminal, the desktop app's Code tab, IDEs.
///
/// Each hook is an async command (Claude never waits on it) that sends the
/// hook's JSON to thenotch's socket with `nc`, and always succeeds, so a
/// closed thenotch shows no "hook error" in Claude Code. The command names
/// the socket path, which is how thenotch finds its own hooks again.
enum ClaudeHooksConfig {
    /// Hook events thenotch listens to.
    static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Notification", "Stop", "StopFailure",
    ]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// The shell command a hook runs.
    static func command(socketPath: String) -> String {
        "/usr/bin/nc -U -w 1 \(shellQuoted(socketPath)) >/dev/null 2>&1 || true"
    }

    enum ConfigError: Error, Equatable {
        /// The settings file isn't a JSON object (or not JSON at all); it's
        /// left alone.
        case unreadable
    }

    // MARK: - Pure

    /// `settings` with thenotch's hook on every event in `events` (any
    /// older one, found by `socketPath`, is replaced), keeping every other
    /// hook and setting.
    static func installing(into settings: [String: Any], socketPath: String) -> [String: Any] {
        let command = command(socketPath: socketPath)
        var settings = removing(from: settings, marker: socketPath)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [Any] ?? []
            groups.append([
                "matcher": "",
                "hooks": [["type": "command", "command": command, "async": true]],
            ])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// `settings` without any hook whose command contains `marker`; groups
    /// and events left empty are removed.
    static func removing(from settings: [String: Any], marker: String) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept: [Any] = groups.compactMap { group in
                guard var group = group as? [String: Any], let entries = group["hooks"] as? [Any] else { return group }
                let remaining = entries.filter { entry in
                    !((entry as? [String: Any])?["command"] as? String ?? "").contains(marker)
                }
                if remaining.isEmpty { return nil }
                group["hooks"] = remaining
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var settings = settings
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// Whether every event has exactly this hook command (an older
    /// command is replaced by `install`).
    static func isInstalled(in settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [Any] ?? []).contains { group in
                ((group as? [String: Any])?["hooks"] as? [Any] ?? []).contains { entry in
                    (entry as? [String: Any])?["command"] as? String == command
                }
            }
        }
    }

    // MARK: - File

    /// Installs the hooks in the settings file, creating it if needed.
    /// Before the first change, the file is copied next to it
    /// (`settings.json.thenotch-backup`).
    static func install(socketPath: String, at url: URL = settingsURL) throws {
        let settings = try read(url)
        guard !isInstalled(in: settings, command: command(socketPath: socketPath)) else { return }
        try write(installing(into: settings, socketPath: socketPath), to: url)
    }

    static func uninstall(socketPath: String, at url: URL = settingsURL) throws {
        let settings = try read(url)
        let updated = removing(from: settings, marker: socketPath)
        guard !NSDictionary(dictionary: updated).isEqual(to: settings) else { return }
        try write(updated, to: url)
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        // Throws if it can't be read: never replace settings we didn't see.
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.unreadable
        }
        return object
    }

    private static func write(_ settings: [String: Any], to url: URL) throws {
        // A symlinked settings file (dotfiles) stays a symlink.
        let url = url.resolvingSymlinksInPath()
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("thenotch-backup")
        if manager.fileExists(atPath: url.path), !manager.fileExists(atPath: backup.path) {
            try manager.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
