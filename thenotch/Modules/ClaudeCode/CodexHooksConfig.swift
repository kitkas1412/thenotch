//
//  CodexHooksConfig.swift
//  thenotch
//

import Foundation

/// Adds thenotch's hooks to Codex's user hooks file (`~/.codex/hooks.json`,
/// learn.chatgpt.com/docs/hooks), and removes them. Same format and rules
/// as `ClaudeHooksConfig` (`AgentHooksFile`); `config.toml` is never touched.
/// Codex asks the user to trust new hooks once (`/hooks` in the CLI, Settings
/// › Hooks in the ChatGPT app).
enum CodexHooksConfig {
    /// Whether hooks are written with `"async": true`. Not known to be
    /// honored by Codex, so they run synchronously: the command is quick
    /// (`nc -w 1`) and always exits 0.
    static let usesAsync = false

    /// Hook events thenotch listens to.
    static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PermissionRequest", "PostToolUse", "Stop",
    ]

    static var hooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    /// The shell command a hook runs.
    static func command(socketPath: String) -> String {
        AgentHooksFile.command(source: .codex, socketPath: socketPath)
    }

    typealias ConfigError = AgentHooksFile.ConfigError

    // MARK: - Pure

    static func installing(into settings: [String: Any], socketPath: String) throws -> [String: Any] {
        try AgentHooksFile.installing(into: settings, events: events, command: command(socketPath: socketPath), marker: socketPath, async: usesAsync)
    }

    static func removing(from settings: [String: Any], marker: String) -> [String: Any] {
        AgentHooksFile.removing(from: settings, marker: marker)
    }

    static func isInstalled(in settings: [String: Any], command: String) -> Bool {
        AgentHooksFile.isInstalled(in: settings, events: events, command: command, async: usesAsync)
    }

    // MARK: - File

    /// Whether Codex is there: its folder (`~/.codex`) exists.
    static func isAvailable(at url: URL = hooksURL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Installs the hooks in the hooks file, creating it if needed. Returns
    /// `false`, changing nothing, if Codex isn't installed (the file's folder
    /// is missing: it isn't created).
    @discardableResult
    static func install(socketPath: String, at url: URL = hooksURL) throws -> Bool {
        guard isAvailable(at: url) else { return false }
        try AgentHooksFile.install(into: url, events: events, command: command(socketPath: socketPath), marker: socketPath, async: usesAsync)
        return true
    }

    static func uninstall(socketPath: String, at url: URL = hooksURL) throws {
        try AgentHooksFile.uninstall(from: url, marker: socketPath)
    }
}
