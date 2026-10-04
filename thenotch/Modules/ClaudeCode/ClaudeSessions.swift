//
//  ClaudeSessions.swift
//  thenotch
//

import Foundation

/// A Claude Code session on this Mac, as its hooks report it.
struct ClaudeSession: Equatable, Identifiable {
    enum State: Equatable {
        /// Between a prompt and Claude's reply.
        case working
        /// A tool is waiting for permission.
        case needsPermission
        /// Claude asked a question (its `AskUserQuestion` tool) and waits
        /// for the answer.
        case asking
        /// Claude asked for input, or has waited for a reply for a while.
        case waitingForInput
        /// Claude finished its reply.
        case idle
    }

    let id: String
    var cwd: String?
    var state: State
    /// While working: the tool running now.
    var tool: String?
    /// With `needsPermission`: what it's for.
    var message: String?
    /// With `asking`: the questions.
    var questions: [ClaudeQuestion] = []
    /// When `state` last changed.
    var since: Date
    /// When the last event came.
    var updatedAt: Date

    /// The project folder's name.
    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Claude Code" }
        return (cwd as NSString).lastPathComponent
    }
}

/// What a hook event means for the island, besides the sessions changing.
enum ClaudeSessionChange: Equatable {
    case none
    /// A session finished its reply: worth a short peek.
    case finished(ClaudeSession)
    /// A session needs the user: permission, or a reply.
    case needsAttention(ClaudeSession)
}

/// Claude Code sessions, updated from hook events. Pure, so it can be
/// unit tested: the module owns one and applies events to it.
struct ClaudeSessions: Equatable {
    /// By session ID.
    private(set) var byID: [String: ClaudeSession] = [:]

    /// Sessions without an event for this long are dropped: a terminal
    /// closed without `SessionEnd` (killed, crashed) leaves one behind.
    static let staleAfter: TimeInterval = 12 * 60 * 60
    /// A session "working" without an event for this long (no reply, no
    /// tool) most likely stopped without `Stop`; it shows as idle.
    static let workingTimeout: TimeInterval = 30 * 60

    /// Most urgent first, then the most recently changed.
    var all: [ClaudeSession] {
        byID.values.sorted { lhs, rhs in
            let (l, r) = (Self.urgency(lhs.state), Self.urgency(rhs.state))
            return l != r ? l > r : lhs.since > rhs.since
        }
    }

    var isEmpty: Bool { byID.isEmpty }

    var needingAttention: [ClaudeSession] {
        all.filter { $0.state == .needsPermission || $0.state == .asking || $0.state == .waitingForInput }
    }

    var working: [ClaudeSession] {
        all.filter { $0.state == .working }
    }

    @discardableResult
    mutating func apply(_ event: ClaudeHookEvent, at date: Date) -> ClaudeSessionChange {
        if event.kind == .sessionEnd {
            byID[event.sessionID] = nil
            return .none
        }
        // A session already running when the app started appears with its
        // first event.
        var session = byID[event.sessionID] ?? ClaudeSession(
            id: event.sessionID, cwd: event.cwd, state: .idle, since: date, updatedAt: date
        )
        if let cwd = event.cwd, session.cwd == nil {
            session.cwd = cwd
        }
        session.updatedAt = date

        var change = ClaudeSessionChange.none
        switch event.kind {
        case .sessionStart:
            break
        case .userPromptSubmit:
            session.set(.working, at: date)
            session.tool = nil
        case .preToolUse where event.toolName == ClaudeHookEvent.askTool:
            session.set(.asking, at: date)
            session.tool = nil
            session.questions = event.questions
            change = .needsAttention(session)
        case .preToolUse:
            session.set(.working, at: date)
            session.tool = event.toolName
        case .postToolUse, .postToolUseFailure:
            // Permission given (or the tool ran): back to work.
            session.set(.working, at: date)
            session.tool = nil
        case .notification:
            switch event.notificationType {
            case .permissionPrompt where session.state == .asking:
                // The question itself: it stays a question.
                break
            case .permissionPrompt:
                session.set(.needsPermission, at: date)
                session.message = event.message
                change = .needsAttention(session)
            case .idlePrompt:
                // A minute after a reply nobody answered: shown in the
                // list, without a peek each time.
                if session.state == .idle {
                    session.set(.waitingForInput, at: date)
                }
            case .agentNeedsInput:
                session.set(.waitingForInput, at: date)
                change = .needsAttention(session)
            case nil:
                break
            }
        case .stop, .stopFailure:
            // A subagent stopping isn't the session's reply.
            guard !event.isSubagent else { break }
            let wasBusy = session.state != .idle && session.state != .waitingForInput
            session.set(.idle, at: date)
            session.tool = nil
            if wasBusy {
                change = .finished(session)
            }
        case .sessionEnd:
            break
        }
        byID[event.sessionID] = session
        return change
    }

    /// Drops stale sessions and settles stuck ones; returns whether
    /// anything changed.
    @discardableResult
    mutating func prune(at date: Date) -> Bool {
        let before = byID
        byID = byID.filter { date.timeIntervalSince($0.value.updatedAt) < Self.staleAfter }
        for (id, session) in byID where session.state == .working
            && date.timeIntervalSince(session.updatedAt) >= Self.workingTimeout {
            byID[id]?.set(.idle, at: date)
        }
        return byID != before
    }

    private static func urgency(_ state: ClaudeSession.State) -> Int {
        switch state {
        case .needsPermission, .asking: 3
        case .waitingForInput: 2
        case .working: 1
        case .idle: 0
        }
    }
}

private extension ClaudeSession {
    mutating func set(_ newState: State, at date: Date) {
        if newState != .needsPermission {
            message = nil
        }
        if newState != .asking {
            questions = []
        }
        guard newState != state else { return }
        state = newState
        since = date
    }
}
