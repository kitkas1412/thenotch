//
//  ClaudeHookEvent.swift
//  thenotch
//

import Foundation

/// A question Claude asks with `AskUserQuestion`: its text and the
/// choices it offers (the answer is given in Claude Code).
struct ClaudeQuestion: Equatable {
    var header: String?
    var text: String
    var options: [String]
    var allowsMultiple: Bool
}

/// One Claude Code hook call, as sent by the hook command over the socket
/// (`ClaudeHookServer`). Only what the island shows is kept: never the
/// prompt, Claude's reply, or a tool's input — except the questions of
/// `AskUserQuestion`, which the island shows.
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
    }

    /// `Notification` hooks' `notification_type`s the island acts on.
    enum NotificationType: String {
        case permissionPrompt = "permission_prompt"
        case idlePrompt = "idle_prompt"
        case agentNeedsInput = "agent_needs_input"
    }

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
    /// `PreToolUse` of `AskUserQuestion`: what Claude asks.
    var questions: [ClaudeQuestion] = []

    /// The tool Claude asks the user a question with.
    static let askTool = "AskUserQuestion"

    /// The payload, at most this large, is read; larger ones are dropped.
    static let maxPayloadSize = 1 << 20

    /// The hook's JSON input (documented at code.claude.com/docs/en/hooks).
    /// `nil` for events the island doesn't use, or without a session.
    static func parse(_ data: Data) -> ClaudeHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let kind = Kind(rawValue: name),
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        return ClaudeHookEvent(
            kind: kind,
            sessionID: sessionID,
            cwd: object["cwd"] as? String,
            toolName: object["tool_name"] as? String,
            notificationType: (object["notification_type"] as? String).flatMap(NotificationType.init),
            message: kind == .notification ? object["message"] as? String : nil,
            isSubagent: object["agent_id"] != nil,
            questions: kind == .preToolUse && object["tool_name"] as? String == askTool
                ? questions(in: object["tool_input"]) : []
        )
    }

    /// `AskUserQuestion`'s input: `{"questions": [{"question", "header",
    /// "options": [{"label", "description"}], "multiSelect"}]}`.
    static func questions(in input: Any?) -> [ClaudeQuestion] {
        let list = (input as? [String: Any])?["questions"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let text = item["question"] as? String, !text.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            return ClaudeQuestion(
                header: item["header"] as? String,
                text: text,
                options: options,
                allowsMultiple: item["multiSelect"] as? Bool ?? false
            )
        }
    }
}
