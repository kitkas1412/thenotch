//
//  ClaudeCodeTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct ClaudeHookEventTests {
    func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func parsesANotification() throws {
        let event = try #require(ClaudeHookEvent.parse(json([
            "hook_event_name": "Notification", "session_id": "s1", "cwd": "/Users/a/thenotch",
            "notification_type": "permission_prompt", "message": "Claude needs your permission to use Bash",
        ])))
        #expect(event.kind == .notification)
        #expect(event.notificationType == .permissionPrompt)
        #expect(event.message == "Claude needs your permission to use Bash")
        #expect(!event.isSubagent)
    }

    @Test func keepsNoPromptOrReply() throws {
        let event = try #require(ClaudeHookEvent.parse(json([
            "hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "secret", "message": "x",
        ])))
        #expect(event.message == nil)
    }

    @Test func keepsTheQuestionsClaudeAsks() throws {
        let event = try #require(ClaudeHookEvent.parse(json([
            "hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [[
                "question": "Which database?", "header": "Storage", "multiSelect": false,
                "options": [["label": "SQLite", "description": "Local"], ["label": "Postgres", "description": "Server"]],
            ]]],
        ])))
        #expect(event.questions == [ClaudeQuestion(header: "Storage", text: "Which database?", options: ["SQLite", "Postgres"], allowsMultiple: false)])
    }

    @Test func keepsNoOtherToolInput() throws {
        let event = try #require(ClaudeHookEvent.parse(json([
            "hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "Bash",
            "tool_input": ["command": "echo secret", "questions": [["question": "x"]]],
        ])))
        #expect(event.questions.isEmpty)
    }

    @Test func ignoresOtherEventsAndBadInput() {
        #expect(ClaudeHookEvent.parse(json(["hook_event_name": "PreCompact", "session_id": "s1"])) == nil)
        #expect(ClaudeHookEvent.parse(json(["hook_event_name": "Stop"])) == nil)
        #expect(ClaudeHookEvent.parse(Data("not json".utf8)) == nil)
    }
}

struct ClaudeSessionsTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func event(_ kind: ClaudeHookEvent.Kind, _ session: String = "s1", tool: String? = nil,
               notification: ClaudeHookEvent.NotificationType? = nil, subagent: Bool = false) -> ClaudeHookEvent {
        ClaudeHookEvent(kind: kind, sessionID: session, cwd: "/Users/a/thenotch", toolName: tool,
                        notificationType: notification, message: notification == .permissionPrompt ? "Allow Bash?" : nil,
                        isSubagent: subagent)
    }

    @Test func aTurnWorksThenFinishes() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.sessionStart), at: start)
        sessions.apply(event(.userPromptSubmit), at: start)
        sessions.apply(event(.preToolUse, tool: "Bash"), at: start)
        #expect(sessions.all.first?.state == .working)
        #expect(sessions.all.first?.tool == "Bash")
        let change = sessions.apply(event(.stop), at: start)
        #expect(sessions.all.first?.state == .idle)
        guard case .finished(let session) = change else {
            Issue.record("expected a finished peek")
            return
        }
        #expect(session.projectName == "thenotch")
    }

    @Test func permissionWaitsUntilTheToolRuns() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.preToolUse, tool: "Bash"), at: start)
        let change = sessions.apply(event(.notification, notification: .permissionPrompt), at: start)
        #expect(sessions.all.first?.state == .needsPermission)
        #expect(sessions.all.first?.message == "Allow Bash?")
        #expect(change != .none)
        sessions.apply(event(.postToolUse, tool: "Bash"), at: start)
        #expect(sessions.all.first?.state == .working)
        #expect(sessions.all.first?.message == nil)
    }

    @Test func aQuestionWaitsForTheAnswer() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        var ask = event(.preToolUse, tool: "AskUserQuestion")
        ask.questions = [ClaudeQuestion(header: nil, text: "Ship it?", options: ["Yes", "No"], allowsMultiple: false)]
        let change = sessions.apply(ask, at: start)
        #expect(sessions.all.first?.state == .asking)
        #expect(sessions.all.first?.questions.first?.text == "Ship it?")
        #expect(change != .none)
        // Its own permission notification doesn't turn it into a permission.
        sessions.apply(event(.notification, notification: .permissionPrompt), at: start)
        #expect(sessions.all.first?.state == .asking)
        sessions.apply(event(.postToolUse, tool: "AskUserQuestion"), at: start)
        #expect(sessions.all.first?.state == .working)
        #expect(sessions.all.first?.questions.isEmpty == true)
    }

    @Test func idlePromptDoesNotPeek() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        sessions.apply(event(.stop), at: start)
        let change = sessions.apply(event(.notification, notification: .idlePrompt), at: start)
        #expect(sessions.all.first?.state == .waitingForInput)
        #expect(change == .none)
    }

    @Test func aSubagentStoppingIsNotTheReply() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        let change = sessions.apply(event(.stop, subagent: true), at: start)
        #expect(change == .none)
        #expect(sessions.all.first?.state == .working)
    }

    @Test func sessionEndRemovesIt() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.sessionStart), at: start)
        sessions.apply(event(.sessionEnd), at: start)
        #expect(sessions.isEmpty)
    }

    @Test func mostUrgentFirst() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit, "working"), at: start)
        sessions.apply(event(.notification, "asking", notification: .permissionPrompt), at: start)
        sessions.apply(event(.sessionStart, "idle"), at: start)
        #expect(sessions.all.map(\.id) == ["asking", "working", "idle"])
    }

    @Test func staleSessionsGoAway() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit, "stuck"), at: start)
        sessions.apply(event(.sessionStart, "old"), at: start.addingTimeInterval(-ClaudeSessions.staleAfter))
        let changed = sessions.prune(at: start.addingTimeInterval(ClaudeSessions.workingTimeout))
        #expect(changed)
        #expect(sessions.all.map(\.id) == ["stuck"])
        #expect(sessions.all.first?.state == .idle)
    }
}

struct ClaudeHooksConfigTests {
    let socket = "/Users/a/Library/Application Support/me.kitkas1412.thenotch/claude-hooks.sock"

    @Test func installKeepsOtherSettingsAndHooks() {
        let mine: [String: Any] = ["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]
        let settings: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [mine]]]
        let installed = ClaudeHooksConfig.installing(into: settings, socketPath: socket)
        #expect(installed["model"] as? String == "opus")
        let pre = (installed["hooks"] as? [String: Any])?["PreToolUse"] as? [Any]
        #expect(pre?.count == 2)
        #expect(ClaudeHooksConfig.isInstalled(in: installed, command: ClaudeHooksConfig.command(socketPath: socket)))
    }

    @Test func installTwiceAddsOnce() {
        let once = ClaudeHooksConfig.installing(into: [:], socketPath: socket)
        let twice = ClaudeHooksConfig.installing(into: once, socketPath: socket)
        let stop = (twice["hooks"] as? [String: Any])?["Stop"] as? [Any]
        #expect(stop?.count == 1)
    }

    @Test func removeLeavesOnlyTheUsersHooks() {
        let mine: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "lint.sh"]]]
        let installed = ClaudeHooksConfig.installing(into: ["hooks": ["Stop": [mine]]], socketPath: socket)
        let removed = ClaudeHooksConfig.removing(from: installed, marker: socket)
        let hooks = removed["hooks"] as? [String: Any]
        #expect(hooks?.keys.sorted() == ["Stop"])
        #expect(NSDictionary(dictionary: removed).isEqual(to: ["hooks": ["Stop": [mine]]]))
        #expect(ClaudeHooksConfig.removing(from: ClaudeHooksConfig.installing(into: [:], socketPath: socket), marker: socket).isEmpty)
    }

    @Test func commandIsAsyncAndNeverFails() {
        let command = ClaudeHooksConfig.command(socketPath: socket)
        #expect(command.hasSuffix("|| true"))
        #expect(command.contains("'\(socket)'"))
        let entry = (((ClaudeHooksConfig.installing(into: [:], socketPath: socket)["hooks"] as? [String: Any])?["Stop"] as? [Any])?.first as? [String: Any])?["hooks"] as? [[String: Any]]
        #expect(entry?.first?["async"] as? Bool == true)
    }

    @Test func fileRoundTripWithBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: url)

        try ClaudeHooksConfig.install(socketPath: socket, at: url)
        #expect(FileManager.default.fileExists(atPath: url.path + ".thenotch-backup"))
        try ClaudeHooksConfig.uninstall(socketPath: socket, at: url)
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(NSDictionary(dictionary: restored ?? [:]).isEqual(to: ["theme": "dark"]))
    }

    @Test func leavesInvalidSettingsAlone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("settings.json")
        try Data("{ // comment".utf8).write(to: url)
        #expect(throws: ClaudeHooksConfig.ConfigError.unreadable) {
            try ClaudeHooksConfig.install(socketPath: socket, at: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ // comment")
    }
}

@MainActor
struct ClaudeQuestionLayoutTests {
    @Test func aLongQuestionFitsThePanel() {
        let question = ClaudeQuestion(header: "Plan", text: "A long question", options: Array(repeating: "Option", count: 9), allowsMultiple: true)
        // The tallest notch (38 pt), the margin below it, and the tab row.
        let island = ClaudeQuestionView.contentHeight(for: question) + 38 + IslandStyle.Spacing.content + IslandState.tabRowHeight
        #expect(island <= IslandController.panelSize.height)
    }
}
