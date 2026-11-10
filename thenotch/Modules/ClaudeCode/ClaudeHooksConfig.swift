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
/// hook's JSON to thenotch's socket (`AgentHooksFile.command`). The command
/// names the socket path, which is how thenotch finds its own hooks again
/// (and replaces an older command, such as one without the source line).
enum ClaudeHooksConfig {
    /// Claude never waits on thenotch's hooks.
    static let usesAsync = true

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
        AgentHooksFile.command(source: .claude, socketPath: socketPath)
    }

    typealias ConfigError = AgentHooksFile.ConfigError

    // MARK: - Pure

    /// `settings` with thenotch's hook on every event in `events` (any
    /// older one, found by `socketPath`, is replaced), keeping every other
    /// hook and setting.
    static func installing(into settings: [String: Any], socketPath: String) throws -> [String: Any] {
        try AgentHooksFile.installing(into: settings, events: events, command: command(socketPath: socketPath), marker: socketPath, async: usesAsync)
    }

    /// `settings` without any hook whose command contains `marker`; groups
    /// and events left empty are removed.
    static func removing(from settings: [String: Any], marker: String) -> [String: Any] {
        AgentHooksFile.removing(from: settings, marker: marker)
    }

    /// Whether every event has exactly this hook command (an older
    /// command is replaced by `install`).
    static func isInstalled(in settings: [String: Any], command: String) -> Bool {
        AgentHooksFile.isInstalled(in: settings, events: events, command: command, async: usesAsync)
    }

    // MARK: - File

    /// Installs the hooks in the settings file, creating it if needed; an
    /// older command of ours is replaced. Before the first change, the file
    /// is copied next to it (`settings.json.thenotch-backup`).
    static func install(socketPath: String, at url: URL = settingsURL) throws {
        try AgentHooksFile.install(into: url, events: events, command: command(socketPath: socketPath), marker: socketPath, async: usesAsync)
    }

    static func uninstall(socketPath: String, at url: URL = settingsURL) throws {
        try AgentHooksFile.uninstall(from: url, marker: socketPath)
    }
}
