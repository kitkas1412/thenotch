//
//  ClaudeCodeModule.swift
//  thenotch
//

import os
import SwiftUI

/// Shows what Claude Code is doing on this Mac, from its hooks
/// (`ClaudeHooksConfig`, `ClaudeHookServer`): beside the notch while a
/// session works, and prominently while one waits for permission; a short
/// peek when a reply is done; every session in the open island.
@MainActor
final class ClaudeCodeModule: IslandModule {
    let id = ModuleKind.claudeCode.id
    /// While a session works: below Now Playing, which it doesn't hide.
    static let workingPriority = 8
    /// A session waiting for permission: above everything, until answered.
    static let permissionPriority = 70
    /// A reply done, or a session asking for input: like the other peeks.
    static let peekPriority = 50
    static let peekDuration: TimeInterval = 4
    /// How often stale sessions are dropped.
    static let pruneInterval: Duration = .seconds(5 * 60)

    private let activities: ActivityCenter
    private let model = ClaudeCodeModel()
    private var server: ClaudeHookServer?
    private var pruneTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?

    private var peekID: String { "\(id).peek" }

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        let server = ClaudeHookServer { [weak self] event in
            self?.handle(event)
        }
        self.server = server
        do {
            try server.start()
        } catch {
            Log.claude.error("Can't listen for Claude Code hooks: \(String(describing: error), privacy: .public)")
            ClaudeCodeStatus.shared.problem = "thenotch can't listen for Claude Code."
            return
        }
        let socketPath = server.path
        Task {
            await ClaudeCodeStatus.shared.installHooks(socketPath: socketPath)
        }
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pruneInterval)
                guard let self, !Task.isCancelled else { return }
                if self.model.sessions.prune(at: .now) {
                    self.refreshActivity()
                }
            }
        }
    }

    func stop() {
        pruneTask?.cancel()
        peekTask?.cancel()
        if let server {
            let socketPath = server.path
            server.stop()
            // Turned off: take the hooks out of Claude Code's settings.
            Task {
                await ClaudeCodeStatus.shared.uninstallHooks(socketPath: socketPath)
            }
        }
        server = nil
        model.sessions = ClaudeSessions()
        model.peek = nil
        activities.remove(id: id)
        activities.remove(id: peekID)
    }

    func compactLeading() -> AnyView {
        AnyView(ClaudeCompactSymbol(model: model))
    }

    func compactTrailing() -> AnyView {
        AnyView(ClaudeCompactStatus(model: model))
    }

    func expandedView() -> AnyView {
        AnyView(ClaudeSessionsView(model: model))
    }

    var hasExpandedContent: Bool {
        !model.sessions.isEmpty
    }

    var expandedContentHeight: CGFloat {
        if let asking = model.asking, let question = asking.questions.first {
            return ClaudeQuestionView.contentHeight(for: question)
        }
        return ClaudeSessionsView.contentHeight(rows: model.sessions.all.count)
    }

    // MARK: - Events

    private func handle(_ event: ClaudeHookEvent) {
        let change = model.sessions.apply(event, at: .now)
        Log.claude.debug("Hook \(event.kind.rawValue, privacy: .public) \(event.toolName ?? event.notificationType?.rawValue ?? "", privacy: .public)")
        switch change {
        case .none:
            break
        case .finished(let session):
            showPeek(.finished(session.projectName))
        case .needsAttention(let session):
            // Permission and questions stay shown until answered; a
            // request for input is a peek.
            if session.state != .needsPermission && session.state != .asking {
                showPeek(.needsInput(session.projectName))
            }
        }
        refreshActivity()
    }

    private func showPeek(_ peek: ClaudeCodeModel.Peek) {
        model.peek = peek
        let endsAt = Date.now.addingTimeInterval(Self.peekDuration)
        activities.publish(LiveActivity(id: peekID, moduleID: id, priority: Self.peekPriority, expiresAt: endsAt))
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.peekDuration))
            guard let self, !Task.isCancelled else { return }
            self.model.peek = nil
        }
    }

    /// The lasting activity: a session waiting for permission or an
    /// answer, else one working, else none.
    private func refreshActivity() {
        let sessions = model.sessions
        if model.waitingState != nil {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.permissionPriority, expiresAt: nil))
        } else if !sessions.working.isEmpty {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.workingPriority, expiresAt: nil))
        } else {
            activities.remove(id: id)
        }
    }
}

@MainActor
@Observable
final class ClaudeCodeModel {
    enum Peek: Equatable {
        case finished(String)
        case needsInput(String)
    }

    var sessions = ClaudeSessions()
    /// The peek showing, if any; it outranks the lasting state.
    var peek: Peek?

    /// A session asking a question that thenotch can show.
    var asking: ClaudeSession? {
        sessions.all.first { $0.state == .asking && !$0.questions.isEmpty }
    }

    /// The most urgent session waiting on the user: for permission, or an
    /// answer to a question.
    var waitingState: ClaudeSession.State? {
        sessions.all.first { $0.state == .needsPermission || $0.state == .asking }?.state
    }
}

/// Whether the hooks are in place, for Settings.
@MainActor
@Observable
final class ClaudeCodeStatus {
    static let shared = ClaudeCodeStatus()

    /// Why it doesn't work, if it doesn't.
    var problem: String?

    func installHooks(socketPath: String) async {
        let result = await Task.detached {
            Result { try ClaudeHooksConfig.install(socketPath: socketPath) }
        }.value
        switch result {
        case .success:
            problem = nil
        case .failure(let error):
            Log.claude.error("Can't add hooks to Claude Code settings: \(String(describing: error), privacy: .public)")
            problem = error as? ClaudeHooksConfig.ConfigError == .unreadable
                ? "~/.claude/settings.json isn't valid JSON, so thenotch left it alone."
                : "thenotch can't update ~/.claude/settings.json."
        }
    }

    func uninstallHooks(socketPath: String) async {
        let result = await Task.detached {
            Result { try ClaudeHooksConfig.uninstall(socketPath: socketPath) }
        }.value
        if case .failure(let error) = result {
            Log.claude.error("Can't remove hooks from Claude Code settings: \(String(describing: error), privacy: .public)")
        }
        problem = nil
    }
}

// MARK: - Views

/// Left wing: a sparkle, pulsing while a session works (not under Reduce
/// Motion, or when nobody can see it).
private struct ClaudeCompactSymbol: View {
    var model: ClaudeCodeModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.allowsAmbientAnimation) private var allowsAmbientAnimation

    var body: some View {
        let isWorking = model.peek == nil && model.waitingState == nil && !model.sessions.working.isEmpty
        Image(systemName: ModuleKind.claudeCode.symbol)
            .font(.islandSymbol(.compact, weight: .semibold))
            .foregroundStyle(model.waitingState != nil ? AnyShapeStyle(IslandSignal.attention) : AnyShapeStyle(.primary))
            .symbolEffect(.pulse, isActive: isWorking && !reduceMotion && allowsAmbientAnimation)
            .accessibilityHidden(true)
    }
}

/// Right wing: the peek, permission, or how many sessions work.
private struct ClaudeCompactStatus: View {
    var model: ClaudeCodeModel

    var body: some View {
        Group {
            switch model.peek {
            case .finished:
                symbol("checkmark", IslandSignal.charging)
            case .needsInput:
                symbol("bubble.left.fill", IslandSignal.attention)
            case nil:
                if model.waitingState == .needsPermission {
                    symbol("hand.raised.fill", IslandSignal.attention)
                } else if model.waitingState == .asking {
                    symbol("questionmark.bubble.fill", IslandSignal.attention)
                } else {
                    let count = model.sessions.working.count
                    Text(count > 1 ? "\(count)" : "")
                        .font(.islandCompact)
                        .foregroundStyle(.primary)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.islandSymbol(.compact, weight: .semibold))
            .foregroundStyle(color)
    }

    private var accessibilityLabel: String {
        switch model.peek {
        case .finished(let project): return "Claude finished in \(project)"
        case .needsInput(let project): return "Claude needs your input in \(project)"
        case nil:
            if model.waitingState == .needsPermission { return "Claude needs your permission" }
            if model.waitingState == .asking { return "Claude asked you a question" }
            return "Claude is working"
        }
    }
}

/// Every session, most urgent first.
struct ClaudeSessionsView: View {
    var model: ClaudeCodeModel

    /// Name over the detail line.
    static let rowHeight: CGFloat = 36
    static let maxRows = 4

    static func contentHeight(rows: Int) -> CGFloat {
        let shown = CGFloat(min(max(rows, 1), maxRows))
        return shown * rowHeight + (shown - 1) * IslandStyle.Spacing.m + IslandStyle.Spacing.content
    }

    var body: some View {
        let sessions = Array(model.sessions.all.prefix(Self.maxRows))
        if let asking = model.asking {
            // A question waiting for an answer: read it here, answer it in
            // Claude Code.
            ClaudeQuestionView(session: asking)
        } else if sessions.isEmpty {
            IslandEmptyState(title: "No Claude Code sessions", message: "Start Claude Code in a terminal or the Claude app.", symbol: "terminal")
        } else {
            // Times are in minutes: once a minute is enough.
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: IslandStyle.Spacing.m) {
                    ForEach(sessions) { session in
                        ClaudeSessionRow(session: session, now: context.date)
                    }
                }
            }
            .islandContentMargins()
        }
    }
}

private struct ClaudeSessionRow: View {
    let session: ClaudeSession
    let now: Date

    var body: some View {
        HStack(spacing: IslandStyle.Spacing.m) {
            Image(systemName: symbol)
                .font(.islandSymbol(.control, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: IslandStyle.Size.control)
            VStack(alignment: .leading, spacing: IslandStyle.Spacing.xxs) {
                Text(session.projectName)
                    .font(.islandHeadline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.islandCaption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: IslandStyle.Spacing.s)
            Text(Self.elapsed(since: session.since, now: now))
                .font(.islandNumeric)
                .foregroundStyle(.secondary)
        }
        .frame(height: ClaudeSessionsView.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch session.state {
        case .working: ModuleKind.claudeCode.symbol
        case .needsPermission: "hand.raised.fill"
        case .asking: "questionmark.bubble.fill"
        case .waitingForInput: "bubble.left.fill"
        case .idle: "checkmark.circle"
        }
    }

    private var tint: AnyShapeStyle {
        switch session.state {
        case .needsPermission, .asking, .waitingForInput: AnyShapeStyle(IslandSignal.attention)
        case .working: AnyShapeStyle(.primary)
        case .idle: AnyShapeStyle(.secondary)
        }
    }

    private var detail: String {
        switch session.state {
        case .working: session.tool.map { "Running \($0)" } ?? "Working…"
        case .needsPermission: session.message ?? "Needs your permission"
        case .asking: "Asked you a question"
        case .waitingForInput: "Waiting for you"
        case .idle: "Done"
        }
    }

    /// "now", "5m", "2h".
    static func elapsed(since date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }
}

/// The question a session asks, with its choices: enough to decide
/// without going back to Claude Code, where it's answered (hooks can't
/// answer it).
struct ClaudeQuestionView: View {
    let session: ClaudeSession

    typealias Spacing = IslandStyle.Spacing
    /// Two lines of the question.
    static let questionHeight: CGFloat = 36
    /// Choices shown; the rest are counted.
    static let maxOptions = 4

    static func contentHeight(for question: ClaudeQuestion) -> CGFloat {
        let rows = CGFloat(optionRows(question.options.count))
        let options = rows > 0 ? rows * IslandStyle.Size.labelLine + (rows - 1) * Spacing.xs + Spacing.s : 0
        // Header, question, choices, footer.
        return IslandStyle.Size.labelLine + Spacing.s + questionHeight + Spacing.s
            + options + IslandStyle.Size.labelLine + Spacing.content
    }

    private static func optionRows(_ count: Int) -> Int {
        count > maxOptions ? maxOptions + 1 : count
    }

    var body: some View {
        if let question = session.questions.first {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "questionmark.bubble.fill")
                        .foregroundStyle(IslandSignal.attention)
                    Text(question.header ?? "Question")
                    if session.questions.count > 1 {
                        Text("1 of \(session.questions.count)")
                    }
                    Spacer()
                    Text(session.projectName)
                }
                .font(.islandLabel)
                .foregroundStyle(.secondary)
                .frame(height: IslandStyle.Size.labelLine)

                Text(question.text)
                    .font(.islandHeadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: Self.questionHeight, maxHeight: Self.questionHeight, alignment: .topLeading)

                if !question.options.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(question.options.prefix(Self.maxOptions).enumerated()), id: \.offset) { _, option in
                            HStack(spacing: Spacing.s) {
                                Image(systemName: question.allowsMultiple ? "square" : "circle")
                                    .font(.islandSymbol(.small, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(option)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(height: IslandStyle.Size.labelLine)
                        }
                        if question.options.count > Self.maxOptions {
                            Text("+\(question.options.count - Self.maxOptions) more")
                                .foregroundStyle(.secondary)
                                .frame(height: IslandStyle.Size.labelLine)
                        }
                    }
                    .font(.islandLabel)
                }

                Text("Answer in Claude Code")
                    .font(.islandCaption)
                    .foregroundStyle(.secondary)
                    .frame(height: IslandStyle.Size.labelLine)
            }
            .islandContentMargins()
            .accessibilityElement(children: .combine)
        }
    }
}
