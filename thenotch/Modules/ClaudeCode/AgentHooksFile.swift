//
//  AgentHooksFile.swift
//  thenotch
//

import Foundation

/// What `ClaudeHooksConfig` and `CodexHooksConfig` share: both agents read
/// user-level hooks as `{"hooks": {"<Event>": [{"matcher": "", "hooks":
/// [{"type": "command", "command": …, "async": true}]}]}}` from a JSON
/// file. This is the only place that knows the format.
enum AgentHooksFile {
    enum ConfigError: Error, Equatable {
        /// The file isn't a JSON object (or not JSON at all); it's left alone.
        case unreadable
        /// Valid JSON, but `hooks` or an event in it isn't what the agent
        /// documents; it's left alone rather than replaced.
        case unexpectedShape
    }

    /// The command a hook runs: a line naming the source, then the hook's
    /// JSON input, sent to thenotch's socket with `nc`. It always
    /// succeeds, so a closed thenotch shows no "hook error". The socket path
    /// in it is how thenotch finds its own hooks again.
    static func command(source: AgentSource, socketPath: String) -> String {
        "{ printf '\(AgentSource.linePrefix)\(source.rawValue)\\n'; cat; } | /usr/bin/nc -U -w 1 \(shellQuoted(socketPath)) >/dev/null 2>&1 || true"
    }

    // MARK: - Pure

    /// The hook entry: `async` is written only when `true` (omitted, the
    /// agent runs the command and waits for it).
    private static func entry(command: String, async: Bool) -> [String: Any] {
        var entry: [String: Any] = ["type": "command", "command": command]
        if async {
            entry["async"] = true
        }
        return entry
    }

    /// `settings` with `command` as a hook on every event (any older hook
    /// of ours, found by `marker`, is replaced), keeping everything else.
    /// Throws `.unexpectedShape` if `hooks` isn't an object or an event's
    /// value isn't an array.
    static func installing(into settings: [String: Any], events: [String], command: String, marker: String, async: Bool) throws -> [String: Any] {
        var settings = removing(from: settings, marker: marker)
        var hooks = [String: Any]()
        if let existing = settings["hooks"] {
            guard let existing = existing as? [String: Any] else { throw ConfigError.unexpectedShape }
            hooks = existing
        }
        for event in events {
            var groups = [Any]()
            if let existing = hooks[event] {
                guard let existing = existing as? [Any] else { throw ConfigError.unexpectedShape }
                groups = existing
            }
            groups.append([
                "matcher": "",
                "hooks": [entry(command: command, async: async)],
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

    /// Whether every event has exactly this hook command, with the same
    /// `async` (a changed shape is reinstalled).
    static func isInstalled(in settings: [String: Any], events: [String], command: String, async: Bool) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [Any] ?? []).contains { group in
                ((group as? [String: Any])?["hooks"] as? [Any] ?? []).contains { entry in
                    guard let entry = entry as? [String: Any] else { return false }
                    return entry["command"] as? String == command
                        && (entry["async"] as? Bool ?? false) == async
                }
            }
        }
    }

    // MARK: - File

    /// An absent file reads as empty; one that isn't a JSON object throws.
    static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        // Throws if it can't be read: never replace settings we didn't see.
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.unreadable
        }
        return object
    }

    /// Writes atomically through symlinks, copying the original once to
    /// `<file>.thenotch-backup`.
    static func write(_ settings: [String: Any], to url: URL) throws {
        // A symlinked file (dotfiles) stays a symlink.
        let url = url.resolvingSymlinksInPath()
        let manager = FileManager.default
        // The atomic write makes a new file: keep the original's permissions.
        let permissions = (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions]
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension(AppIdentity.backupExtension)
        if manager.fileExists(atPath: url.path), !manager.fileExists(atPath: backup.path) {
            try manager.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        if let permissions {
            try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    static func install(into url: URL, events: [String], command: String, marker: String, async: Bool) throws {
        let settings = try read(url)
        guard !isInstalled(in: settings, events: events, command: command, async: async) else { return }
        try write(installing(into: settings, events: events, command: command, marker: marker, async: async), to: url)
    }

    static func uninstall(from url: URL, marker: String) throws {
        let settings = try read(url)
        let updated = removing(from: settings, marker: marker)
        guard !NSDictionary(dictionary: updated).isEqual(to: settings) else { return }
        try write(updated, to: url)
    }

    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
