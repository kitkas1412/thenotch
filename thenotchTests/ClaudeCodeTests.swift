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

    @Test func keepsNoQuestionText() throws {
        let data = json([
            "hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [[
                "question": "Which database?", "header": "Storage", "multiSelect": false,
                "options": [["label": "SQLite", "description": "Local"]],
            ]]],
        ])
        let event = try #require(ClaudeHookEvent.parse(data))
        #expect(event.toolName == ClaudeHookEvent.askTool)
        #expect(event.message == nil)
        let dump = String(describing: event)
        for secret in ["Which database?", "Storage", "SQLite", "Local"] {
            #expect(!dump.contains(secret))
        }
        var sessions = ClaudeSessions()
        sessions.apply(event, at: Date(timeIntervalSinceReferenceDate: 1))
        #expect(sessions.all.first?.state == .asking)
    }

    @Test func keepsNoOtherToolInput() throws {
        let event = try #require(ClaudeHookEvent.parse(json([
            "hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "Bash",
            "tool_input": ["command": "echo secret"],
        ])))
        #expect(event.toolName == "Bash")
        #expect(!String(describing: event).contains("secret"))
    }

    @Test func parsesTheSourceLine() throws {
        let body = json(["hook_event_name": "Stop", "session_id": "s1"])
        let codex = try #require(ClaudeHookEvent.parse(Data("thenotch-source: codex\n".utf8) + body))
        #expect(codex.source == .codex)
        #expect(codex.kind == .stop)
        let claude = try #require(ClaudeHookEvent.parse(Data("thenotch-source: claude\n".utf8) + body))
        #expect(claude.source == .claude)
        #expect(try #require(ClaudeHookEvent.parse(body)).source == .claude)
        #expect(ClaudeHookEvent.parse(Data("thenotch-source: gemini\n".utf8) + body) == nil)
    }

    @Test func parsesAPermissionRequest() throws {
        let event = try #require(ClaudeHookEvent.parse(json([
            "hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash",
        ])))
        #expect(event.kind == .permissionRequest)
    }

    @Test func ignoresOtherEventsAndBadInput() {
        #expect(ClaudeHookEvent.parse(json(["hook_event_name": "PreCompact", "session_id": "s1"])) == nil)
        #expect(ClaudeHookEvent.parse(json(["hook_event_name": "Stop"])) == nil)
        #expect(ClaudeHookEvent.parse(Data("not json".utf8)) == nil)
    }
}

struct AgentSourceTests {
    let body = Data(#"{"a":1}"#.utf8)

    @Test func noPrefixIsClaudeWithTheWholePayload() throws {
        let result = try #require(AgentSource.split(body))
        #expect(result.source == .claude)
        #expect(result.json == body)
    }

    @Test func knownPrefixGivesSourceAndJSONAfterTheFirstNewline() throws {
        for source in AgentSource.allCases {
            let result = try #require(AgentSource.split(Data("thenotch-source: \(source.rawValue)\n".utf8) + body))
            #expect(result.source == source)
            #expect(result.json == body)
        }
    }

    @Test func onlyTheFirstNewlineSplits() throws {
        let multi = Data("{\n\"a\": 1\n}".utf8)
        let result = try #require(AgentSource.split(Data("thenotch-source: codex\n".utf8) + multi))
        #expect(result.json == multi)
    }

    @Test func unknownSourceIsRejected() {
        #expect(AgentSource.split(Data("thenotch-source: gemini\n".utf8) + body) == nil)
    }

    @Test func prefixWithoutNewlineIsRejected() {
        #expect(AgentSource.split(Data("thenotch-source: codex".utf8)) == nil)
    }
}

struct AgentElapsedTests {
    @Test func formatsMinutesAndHours() {
        #expect(AgentElapsed.format(0) == "0:00")
        #expect(AgentElapsed.format(307) == "5:07")
        #expect(AgentElapsed.format(3599) == "59:59")
        #expect(AgentElapsed.format(3600) == "1:00:00")
    }

    @Test func negativeIsZero() {
        #expect(AgentElapsed.format(-5) == "0:00")
    }
}

struct ClaudeSessionsTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func event(_ kind: ClaudeHookEvent.Kind, _ session: String = "s1", tool: String? = nil,
               notification: ClaudeHookEvent.NotificationType? = nil, subagent: Bool = false,
               source: AgentSource = .claude) -> ClaudeHookEvent {
        ClaudeHookEvent(source: source, kind: kind, sessionID: session, cwd: "/Users/a/thenotch", toolName: tool,
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
        let change = sessions.apply(event(.preToolUse, tool: "AskUserQuestion"), at: start)
        #expect(sessions.all.first?.state == .asking)
        #expect(change != .none)
        // Its own permission notification doesn't turn it into a permission.
        sessions.apply(event(.notification, notification: .permissionPrompt), at: start)
        #expect(sessions.all.first?.state == .asking)
        sessions.apply(event(.postToolUse, tool: "AskUserQuestion"), at: start)
        #expect(sessions.all.first?.state == .working)
    }

    @Test func permissionRequestWaitsUntilTheToolRuns() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.preToolUse, tool: "Bash", source: .codex), at: start)
        let change = sessions.apply(event(.permissionRequest, tool: "Bash", source: .codex), at: start)
        #expect(sessions.all.first?.state == .needsPermission)
        guard case .needsAttention(let session) = change else {
            Issue.record("expected needsAttention")
            return
        }
        #expect(session.source == .codex)
        sessions.apply(event(.postToolUse, tool: "Bash", source: .codex), at: start)
        #expect(sessions.all.first?.state == .working)
    }

    @Test func sameIDFromDifferentSourcesAreTwoSessions() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit, "x", source: .claude), at: start)
        sessions.apply(event(.userPromptSubmit, "x", source: .codex), at: start)
        #expect(sessions.all.count == 2)
        #expect(Set(sessions.all.map(\.key)) == ["claude:x", "codex:x"])
        sessions.apply(event(.sessionEnd, "x", source: .codex), at: start)
        #expect(sessions.all.map(\.key) == ["claude:x"])
    }

    @Test func turnStartsAtThePromptAndSurvivesToolEvents() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        #expect(sessions.all.first?.turnStartedAt == start)
        sessions.apply(event(.preToolUse, tool: "Bash"), at: start.addingTimeInterval(5))
        sessions.apply(event(.permissionRequest), at: start.addingTimeInterval(6))
        sessions.apply(event(.postToolUse, tool: "Bash"), at: start.addingTimeInterval(9))
        #expect(sessions.all.first?.turnStartedAt == start)
    }

    @Test func firstToolStartsTheTurnWhenThereWasNoPrompt() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.sessionStart), at: start)
        #expect(sessions.all.first?.turnStartedAt == nil)
        sessions.apply(event(.preToolUse, tool: "Bash"), at: start.addingTimeInterval(3))
        #expect(sessions.all.first?.turnStartedAt == start.addingTimeInterval(3))
    }

    @Test func aNewPromptRestartsTheTurn() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        sessions.apply(event(.userPromptSubmit), at: start.addingTimeInterval(20))
        #expect(sessions.all.first?.turnStartedAt == start.addingTimeInterval(20))
    }

    @Test func stopClearsTheTurnButASubagentStopDoesNot() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        sessions.apply(event(.stop, subagent: true), at: start.addingTimeInterval(4))
        #expect(sessions.all.first?.turnStartedAt == start)
        sessions.apply(event(.stop), at: start.addingTimeInterval(8))
        #expect(sessions.all.first?.turnStartedAt == nil)

        sessions.apply(event(.userPromptSubmit, "f"), at: start)
        sessions.apply(event(.stopFailure, "f"), at: start.addingTimeInterval(2))
        #expect(sessions.all.first { $0.id == "f" }?.turnStartedAt == nil)
    }

    @Test func pruningAStuckSessionClearsTheTurn() {
        var sessions = ClaudeSessions()
        sessions.apply(event(.userPromptSubmit), at: start)
        sessions.prune(at: start.addingTimeInterval(ClaudeSessions.workingTimeout))
        #expect(sessions.all.first?.state == .idle)
        #expect(sessions.all.first?.turnStartedAt == nil)
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

    @Test func installKeepsOtherSettingsAndHooks() throws {
        let mine: [String: Any] = ["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]
        let settings: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [mine]]]
        let installed = try ClaudeHooksConfig.installing(into: settings, socketPath: socket)
        #expect(installed["model"] as? String == "opus")
        let pre = (installed["hooks"] as? [String: Any])?["PreToolUse"] as? [Any]
        #expect(pre?.count == 2)
        #expect(ClaudeHooksConfig.isInstalled(in: installed, command: ClaudeHooksConfig.command(socketPath: socket)))
    }

    @Test func installTwiceAddsOnce() throws {
        let once = try ClaudeHooksConfig.installing(into: [:], socketPath: socket)
        let twice = try ClaudeHooksConfig.installing(into: once, socketPath: socket)
        let stop = (twice["hooks"] as? [String: Any])?["Stop"] as? [Any]
        #expect(stop?.count == 1)
    }

    @Test func removeLeavesOnlyTheUsersHooks() throws {
        let mine: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "lint.sh"]]]
        let installed = try ClaudeHooksConfig.installing(into: ["hooks": ["Stop": [mine]]], socketPath: socket)
        let removed = ClaudeHooksConfig.removing(from: installed, marker: socket)
        let hooks = removed["hooks"] as? [String: Any]
        #expect(hooks?.keys.sorted() == ["Stop"])
        #expect(NSDictionary(dictionary: removed).isEqual(to: ["hooks": ["Stop": [mine]]]))
        #expect(ClaudeHooksConfig.removing(from: try ClaudeHooksConfig.installing(into: [:], socketPath: socket), marker: socket).isEmpty)
    }

    @Test func commandIsAsyncAndNeverFails() throws {
        let command = ClaudeHooksConfig.command(socketPath: socket)
        #expect(command.hasSuffix("|| true"))
        #expect(command.contains("'\(socket)'"))
        #expect(command.contains("thenotch-source: claude"))
        let entry = (((try ClaudeHooksConfig.installing(into: [:], socketPath: socket)["hooks"] as? [String: Any])?["Stop"] as? [Any])?.first as? [String: Any])?["hooks"] as? [[String: Any]]
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

struct ClaudeHooksUpgradeTests {
    let socket = "/Users/a/Library/Application Support/me.kitkas1412.thenotch/claude-hooks.sock"

    @Test func anOldUntaggedCommandIsReplacedOncePerEvent() throws {
        let old: [String: Any] = ["matcher": "", "hooks": [[
            "type": "command", "command": "nc -U -w 1 '\(socket)' || true", "async": true,
        ]]]
        let mine: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "lint.sh"]]]
        var hooks: [String: Any] = [:]
        for event in ClaudeHooksConfig.events { hooks[event] = [old] }
        hooks["Stop"] = [mine, old]
        let upgraded = try ClaudeHooksConfig.installing(into: ["hooks": hooks], socketPath: socket)
        let newCommand = ClaudeHooksConfig.command(socketPath: socket)
        let result = upgraded["hooks"] as? [String: Any]
        for event in ClaudeHooksConfig.events {
            let commands = ((result?[event] as? [Any]) ?? []).flatMap { group in
                ((group as? [String: Any])?["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
            #expect(commands.filter { $0.contains(socket) } == [newCommand], "event \(event)")
        }
        #expect(((result?["Stop"] as? [Any])?.count) == 2)
        #expect(ClaudeHooksConfig.isInstalled(in: upgraded, command: newCommand))
    }
}

struct CodexHooksConfigTests {
    let socket = "/Users/a/Library/Application Support/me.kitkas1412.thenotch/claude-hooks.sock"

    func tempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func commandIsTaggedCodexAndNeverFails() {
        let command = CodexHooksConfig.command(socketPath: socket)
        #expect(command.contains("thenotch-source: codex"))
        #expect(command.contains("'\(socket)'"))
        #expect(command.hasSuffix("|| true"))
    }

    @Test func installKeepsOtherSettingsAndHooks() throws {
        let mine: [String: Any] = ["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]
        let installed = try CodexHooksConfig.installing(into: ["x": 1, "hooks": ["PreToolUse": [mine]]], socketPath: socket)
        #expect(installed["x"] as? Int == 1)
        let hooks = installed["hooks"] as? [String: Any]
        #expect((hooks?["PreToolUse"] as? [Any])?.count == 2)
        #expect(Set(hooks?.keys ?? [:].keys) == Set(CodexHooksConfig.events))
        #expect(CodexHooksConfig.isInstalled(in: installed, command: CodexHooksConfig.command(socketPath: socket)))
    }

    @Test func installTwiceAddsOnce() throws {
        let once = try CodexHooksConfig.installing(into: [:], socketPath: socket)
        let twice = try CodexHooksConfig.installing(into: once, socketPath: socket)
        #expect(NSDictionary(dictionary: once).isEqual(to: twice))
        #expect(((twice["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1)
    }

    @Test func removeLeavesOnlyTheUsersHooks() throws {
        let mine: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "lint.sh"]]]
        let installed = try CodexHooksConfig.installing(into: ["hooks": ["Stop": [mine]]], socketPath: socket)
        let removed = CodexHooksConfig.removing(from: installed, marker: socket)
        #expect(NSDictionary(dictionary: removed).isEqual(to: ["hooks": ["Stop": [mine]]]))
    }

    @Test func fileRoundTripWithBackup() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("hooks.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: url)

        #expect(try CodexHooksConfig.install(socketPath: socket, at: url))
        #expect(FileManager.default.fileExists(atPath: url.path + ".thenotch-backup"))
        let installed = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(CodexHooksConfig.isInstalled(in: installed, command: CodexHooksConfig.command(socketPath: socket)))

        // A second install doesn't overwrite the one-time backup.
        try CodexHooksConfig.install(socketPath: socket, at: url)
        #expect(try String(contentsOfFile: url.path + ".thenotch-backup", encoding: .utf8) == #"{"theme":"dark"}"#)

        try CodexHooksConfig.uninstall(socketPath: socket, at: url)
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(NSDictionary(dictionary: restored ?? [:]).isEqual(to: ["theme": "dark"]))
    }

    @Test func createsTheFileWhenTheFolderExists() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("hooks.json")
        #expect(CodexHooksConfig.isAvailable(at: url))
        #expect(try CodexHooksConfig.install(socketPath: socket, at: url))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func leavesInvalidJSONAlone() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("hooks.json")
        try Data("{ // comment".utf8).write(to: url)
        #expect(throws: CodexHooksConfig.ConfigError.unreadable) {
            try CodexHooksConfig.install(socketPath: socket, at: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ // comment")
    }

    @Test func missingFolderMeansCodexIsNotInstalled() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent(".codex", isDirectory: true)
        let url = missing.appendingPathComponent("hooks.json")
        #expect(!CodexHooksConfig.isAvailable(at: url))
        #expect(try CodexHooksConfig.install(socketPath: socket, at: url) == false)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}

struct AgentHooksFileShapeTests {
    let socket = "/Users/a/Library/Application Support/me.kitkas1412.thenotch/claude-hooks.sock"

    func tempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func entries(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    @Test func claudeEntriesAreAsyncAndCodexEntriesHaveNoAsyncKey() throws {
        #expect(CodexHooksConfig.usesAsync == false)
        let claude = try ClaudeHooksConfig.installing(into: [:], socketPath: socket)
        let codex = try CodexHooksConfig.installing(into: [:], socketPath: socket)
        for event in ClaudeHooksConfig.events {
            #expect(entries(claude, event).count == 1)
            #expect(entries(claude, event).first?["async"] as? Bool == true, "claude \(event)")
        }
        for event in CodexHooksConfig.events {
            #expect(entries(codex, event).count == 1)
            #expect(entries(codex, event).first?.keys.contains("async") == false, "codex \(event)")
        }
    }

    @Test func anEntryWithADifferentAsyncIsNotInstalledAndIsRewrittenOnce() throws {
        let command = CodexHooksConfig.command(socketPath: socket)
        let stale = CodexHooksConfig.events.reduce(into: [String: Any]()) { hooks, event in
            hooks[event] = [["matcher": "", "hooks": [["type": "command", "command": command, "async": true]]]]
        }
        let settings: [String: Any] = ["hooks": stale]
        #expect(!CodexHooksConfig.isInstalled(in: settings, command: command))

        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("hooks.json")
        try JSONSerialization.data(withJSONObject: settings).write(to: url)
        #expect(try CodexHooksConfig.install(socketPath: socket, at: url))
        let result = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(CodexHooksConfig.isInstalled(in: result, command: command))
        for event in CodexHooksConfig.events {
            #expect(entries(result, event).count == 1, "event \(event)")
            #expect(entries(result, event).first?.keys.contains("async") == false)
        }
    }

    @Test(arguments: [
        #"{"hooks": []}"#,
        #"{"hooks": {"Stop": {}}}"#,
    ])
    func unexpectedShapeThrowsAndTheFileIsUntouched(_ json: String) throws {
        let settings = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(throws: AgentHooksFile.ConfigError.unexpectedShape) {
            try ClaudeHooksConfig.installing(into: settings, socketPath: socket)
        }
        #expect(throws: AgentHooksFile.ConfigError.unexpectedShape) {
            try CodexHooksConfig.installing(into: settings, socketPath: socket)
        }
        // Removing never destroys what it doesn't understand.
        #expect(NSDictionary(dictionary: ClaudeHooksConfig.removing(from: settings, marker: socket)).isEqual(to: settings))
        #expect(NSDictionary(dictionary: CodexHooksConfig.removing(from: settings, marker: socket)).isEqual(to: settings))

        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("hooks.json")
        try Data(json.utf8).write(to: url)
        #expect(throws: AgentHooksFile.ConfigError.unexpectedShape) {
            try CodexHooksConfig.install(socketPath: socket, at: url)
        }
        #expect(throws: AgentHooksFile.ConfigError.unexpectedShape) {
            try ClaudeHooksConfig.install(socketPath: socket, at: url)
        }
        #expect(try Data(contentsOf: url) == Data(json.utf8))
        try CodexHooksConfig.uninstall(socketPath: socket, at: url)
        #expect(try Data(contentsOf: url) == Data(json.utf8))
    }

    @Test func installAndUninstallKeepTheFilePermissions() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("hooks.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        func permissions() throws -> Int? {
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        }
        try CodexHooksConfig.install(socketPath: socket, at: url)
        #expect(try permissions() == 0o600)
        try CodexHooksConfig.uninstall(socketPath: socket, at: url)
        #expect(try permissions() == 0o600)
    }
}

struct ClaudeSessionsPermissionPruneTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func waitingForPermission() -> ClaudeSessions {
        var sessions = ClaudeSessions()
        sessions.apply(ClaudeHookEvent(source: .claude, kind: .userPromptSubmit, sessionID: "s1", cwd: nil, toolName: nil,
                                       notificationType: nil, message: nil, isSubagent: false), at: start)
        sessions.apply(ClaudeHookEvent(source: .claude, kind: .notification, sessionID: "s1", cwd: nil, toolName: nil,
                                       notificationType: .permissionPrompt, message: nil, isSubagent: false), at: start)
        return sessions
    }

    @Test func aStalePermissionRequestBecomesIdleWithoutATurn() {
        var sessions = waitingForPermission()
        #expect(sessions.all.first?.state == .needsPermission)
        let changed = sessions.prune(at: start.addingTimeInterval(ClaudeSessions.workingTimeout))
        #expect(changed)
        #expect(sessions.all.first?.state == .idle)
        #expect(sessions.all.first?.turnStartedAt == nil)
    }

    @Test func aRecentPermissionRequestIsUnchanged() {
        var sessions = waitingForPermission()
        let changed = sessions.prune(at: start.addingTimeInterval(ClaudeSessions.workingTimeout - 1))
        #expect(!changed)
        #expect(sessions.all.first?.state == .needsPermission)
        #expect(sessions.all.first?.turnStartedAt != nil)
    }
}

struct AgentSourceCRLFTests {
    @Test func aCRLFAfterTheSourceLineStillGivesCodexAndParsableJSON() throws {
        let payload = Data("\(AgentSource.linePrefix)codex\r\n{\"hook_event_name\":\"Stop\",\"session_id\":\"x\"}".utf8)
        let (source, json) = try #require(AgentSource.split(payload))
        #expect(source == .codex)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["session_id"] as? String == "x")
        #expect(ClaudeHookEvent.parse(payload)?.source == .codex)
    }
}
