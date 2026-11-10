//
//  ClaudeHookEvent.swift
//  thenotch
//

import Foundation

/// The coding agent a hook call comes from.
enum AgentSource: String, Equatable, CaseIterable {
    case claude
    case codex

    /// Shown as plain text next to a session.
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The hook command's first line before the JSON: `thenotch-source: <raw value>`.
    static let linePrefix = "thenotch-source: "

    /// The source named by the first line of a payload and the JSON after
    /// it. A payload without that line (hooks installed by an older
    /// version) is Claude's, whole. `nil` for a line naming an unknown source.
    static func split(_ data: Data) -> (source: AgentSource, json: Data)? {
        let prefix = Data(linePrefix.utf8)
        guard data.starts(with: prefix) else { return (.claude, data) }
        let rest = data.dropFirst(prefix.count)
        guard let newline = rest.firstIndex(of: 0x0A) else { return nil }
        let name = String(decoding: rest[rest.startIndex..<newline], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = AgentSource(rawValue: name) else { return nil }
        return (source, Data(rest[rest.index(after: newline)...]))
    }
}

/// One Claude Code or Codex hook call, as sent by the hook command over
/// the socket (`ClaudeHookServer`). Only what the island shows is kept:
/// never the prompt, the reply, a tool's input or a question.
struct ClaudeHookEvent: Equatable {
    enum Kind: String {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case notification = "Notification"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        /// Codex: a tool waits for approval.
        case permissionRequest = "PermissionRequest"
    }

    /// `Notification` hooks' `notification_type`s the island acts on.
    enum NotificationType: String {
        case permissionPrompt = "permission_prompt"
        case idlePrompt = "idle_prompt"
        case agentNeedsInput = "agent_needs_input"
    }

    let source: AgentSource
    let kind: Kind
    let sessionID: String
    /// The session's working directory.
    let cwd: String?
    /// `PreToolUse`/`PostToolUse`: the tool, such as `Bash` or `Edit`.
    let toolName: String?
    /// `Notification`: what it's about; `nil` for types the island ignores.
    let notificationType: NotificationType?
    /// `Notification`: its text, such as "Claude needs your permission to
    /// use Bash".
    let message: String?
    /// Inside a subagent (its events count for the session).
    let isSubagent: Bool

    /// The tool Claude asks the user a question with.
    static let askTool = "AskUserQuestion"

    /// The payload, at most this large, is read; larger ones are dropped.
    static let maxPayloadSize = 1 << 20

    /// The hook command's output: an optional source line (`AgentSource.split`)
    /// then the hook's JSON input (documented at code.claude.com/docs/en/hooks
    /// and learn.chatgpt.com/docs/hooks). `nil` for events the island
    /// doesn't use, or without a session.
    static func parse(_ data: Data) -> ClaudeHookEvent? {
        guard let (source, json) = AgentSource.split(data),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let kind = Kind(rawValue: name),
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        return ClaudeHookEvent(
            source: source,
            kind: kind,
            sessionID: sessionID,
            cwd: object["cwd"] as? String,
            toolName: object["tool_name"] as? String,
            notificationType: (object["notification_type"] as? String).flatMap(NotificationType.init),
            message: kind == .notification ? object["message"] as? String : nil,
            isSubagent: object["agent_id"] != nil
        )
    }
}
