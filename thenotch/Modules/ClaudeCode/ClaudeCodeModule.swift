//
//  ClaudeCodeModule.swift
//  thenotch
//

import os
import SwiftUI

/// Shows what Claude Code and Codex are doing on this Mac, from their hooks
/// (`ClaudeHooksConfig`, `CodexHooksConfig`, `ClaudeHookServer`): beside the notch while a
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
    /// Sleeps until the run time gains a digit (10 min, 1 h).
    private var widthTask: Task<Void, Never>?

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
            ClaudeCodeStatus.shared.problem = "\(AppIdentity.name) can't listen for Claude Code or Codex."
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
        let socketPath = server?.path
        suspend()
        // Turned off: take the hooks out of Claude Code's settings.
        if let socketPath {
            Task {
                await ClaudeCodeStatus.shared.uninstallHooks(socketPath: socketPath)
            }
        }
    }

    /// Stops listening but leaves the hooks in place: they fail silently
    /// (`|| true`) while nothing listens, and `start()` finds them again.
    func suspend() {
        pruneTask?.cancel()
        peekTask?.cancel()
        widthTask?.cancel()
        widthTask = nil
        server?.stop()
        server = nil
        model.sessions = ClaudeSessions()
        model.peek = nil
        model.elapsedWidth = .short
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

    /// Wide enough for the elapsed time while any session works, even when
    /// a peek or permission request briefly replaces it (no width jumps).
    /// The width grows as the time gains digits (`model.elapsedWidth`).
    var compactContentWidth: CGFloat {
        model.sessions.working.isEmpty ? IslandStyle.Size.compactContent : model.elapsedWidth.width
    }

    var expandedContentHeight: CGFloat {
        return ClaudeSessionsView.contentHeight(rows: model.sessions.all.count)
    }

    // MARK: - Events

    private func handle(_ event: ClaudeHookEvent) {
        let change = model.sessions.apply(event, at: .now)
        Log.claude.debug("Hook \(event.source.rawValue, privacy: .public) \(event.kind.rawValue, privacy: .public) \(event.toolName ?? event.notificationType?.rawValue ?? "", privacy: .public)")
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
        refreshElapsedWidth()
        let sessions = model.sessions
        if model.waitingState != nil {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.permissionPriority, expiresAt: nil))
        } else if !sessions.working.isEmpty {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.workingPriority, expiresAt: nil))
        } else {
            activities.remove(id: id)
        }
    }

    /// Sets the width class for the longest turn's run time and sleeps
    /// until it changes (one task, no polling).
    private func refreshElapsedWidth() {
        widthTask?.cancel()
        widthTask = nil
        guard let start = model.longestTurnStart else {
            model.elapsedWidth = .short
            return
        }
        let elapsed = Date.now.timeIntervalSince(start)
        let current = AgentElapsed.WidthClass(seconds: elapsed)
        model.elapsedWidth = current
        guard let threshold = current.nextThreshold else { return }
        // A hair late, so the time has the extra digit when the width grows.
        let delay = max(0, threshold - elapsed) + 0.05
        widthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.refreshElapsedWidth()
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
    /// How wide the longest run time is; kept current by the module.
    var elapsedWidth: AgentElapsed.WidthClass = .short

    /// Whether the right wing shows a run time: sessions work and nothing
    /// outranks it.
    var showsElapsed: Bool {
        peek == nil && waitingState == nil && !sessions.working.isEmpty
    }

    /// When the longest-running working session's turn began.
    var longestTurnStart: Date? {
        sessions.working.compactMap { $0.turnStartedAt ?? $0.since }.min()
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

    /// Why Claude Code's hooks don't work, if they don't.
    var problem: String?
    /// Why Codex's hooks don't work, if they don't. Independent of Claude's.
    var codexProblem: String?

    func installHooks(socketPath: String) async {
        let result = await Task.detached {
            Result { try ClaudeHooksConfig.install(socketPath: socketPath) }
        }.value
        switch result {
        case .success:
            problem = nil
        case .failure(let error):
            Log.claude.error("Can't add hooks to Claude Code settings: \(String(describing: error), privacy: .public)")
            problem = error as? ClaudeHooksConfig.ConfigError == .unexpectedShape
                ? "~/.claude/settings.json has an unexpected \"hooks\" format, so \(AppIdentity.name) left it alone."
                : error as? ClaudeHooksConfig.ConfigError == .unreadable
                ? "~/.claude/settings.json isn't valid JSON, so \(AppIdentity.name) left it alone."
                : "\(AppIdentity.name) can't update ~/.claude/settings.json."
        }
        // Skipped silently when Codex isn't installed.
        let codex = await Task.detached {
            Result { try CodexHooksConfig.install(socketPath: socketPath) }
        }.value
        switch codex {
        case .success:
            codexProblem = nil
        case .failure(let error):
            Log.claude.error("Can't add hooks to Codex hooks file: \(String(describing: error), privacy: .public)")
            codexProblem = error as? CodexHooksConfig.ConfigError == .unexpectedShape
                ? "~/.codex/hooks.json has an unexpected \"hooks\" format, so \(AppIdentity.name) left it alone."
                : error as? CodexHooksConfig.ConfigError == .unreadable
                ? "~/.codex/hooks.json isn't valid JSON, so \(AppIdentity.name) left it alone."
                : "\(AppIdentity.name) can't update ~/.codex/hooks.json."
        }
    }

    func uninstallHooks(socketPath: String) async {
        let result = await Task.detached {
            Result { try ClaudeHooksConfig.uninstall(socketPath: socketPath) }
        }.value
        if case .failure(let error) = result {
            Log.claude.error("Can't remove hooks from Claude Code settings: \(String(describing: error), privacy: .public)")
        }
        let codex = await Task.detached {
            Result { try CodexHooksConfig.uninstall(socketPath: socketPath) }
        }.value
        if case .failure(let error) = codex {
            Log.claude.error("Can't remove hooks from Codex hooks file: \(String(describing: error), privacy: .public)")
        }
        problem = nil
        codexProblem = nil
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
            // Fill the wing and sit at its outer edge (padding = compactPadding).
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The run time `AgentElapsed.format`, ticking every second while the
/// island can be seen (a static value otherwise).
private struct ClaudeElapsedText: View {
    let start: Date
    let font: Font

    @Environment(\.allowsAmbientAnimation) private var allowsAmbientAnimation

    var body: some View {
        if allowsAmbientAnimation {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                text(at: context.date)
            }
        } else {
            text(at: .now)
        }
    }

    private func text(at date: Date) -> some View {
        Text(AgentElapsed.format(date.timeIntervalSince(start)))
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}

/// Right wing: the peek, permission, or the longest run time of the working sessions.
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
                    if let start = model.longestTurnStart {
                        ClaudeElapsedText(start: start, font: .islandCompact)
                    }
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
        case .finished(let project): return "Agent finished in \(project)"
        case .needsInput(let project): return "Agent needs your input in \(project)"
        case nil:
            if model.waitingState == .needsPermission { return "An agent needs your permission" }
            if model.waitingState == .asking { return "An agent asked you a question" }
            let count = model.sessions.working.count
            return count > 1 ? "\(count) agent sessions are working" : "An agent session is working"
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

    @Environment(\.allowsAmbientAnimation) private var allowsAmbientAnimation

    var body: some View {
        let sessions = Array(model.sessions.all.prefix(Self.maxRows))
        if sessions.isEmpty {
            IslandEmptyState(title: "No agent sessions", message: "Start Claude Code or Codex in a terminal or their app.", symbol: "terminal")
        } else if allowsAmbientAnimation, sessions.contains(where: { $0.state == .working }) {
            // Run times count seconds (not while the display is asleep).
            TimelineView(.periodic(from: .now, by: 1)) { context in
                list(sessions, now: context.date)
            }
            .islandContentMargins()
        } else {
            // Times are in minutes: once a minute is enough.
            TimelineView(.everyMinute) { context in
                list(sessions, now: context.date)
            }
            .islandContentMargins()
        }
    }

    private func list(_ sessions: [ClaudeSession], now: Date) -> some View {
        VStack(alignment: .leading, spacing: IslandStyle.Spacing.m) {
            ForEach(sessions, id: \.key) { session in
                ClaudeSessionRow(session: session, now: now)
            }
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
                HStack(spacing: IslandStyle.Spacing.xs) {
                    Text(session.projectName)
                        .font(.islandHeadline)
                        .foregroundStyle(.primary)
                    Text(session.source.displayName)
                        .font(.islandCaption)
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.islandCaption)
                    .foregroundStyle(session.state == .asking ? AnyShapeStyle(IslandSignal.attention) : AnyShapeStyle(.secondary))
            }
            .lineLimit(1)
            Spacer(minLength: IslandStyle.Spacing.s)
            Text(trailing)
                .font(.islandNumeric)
                .foregroundStyle(.secondary)
        }
        .frame(height: ClaudeSessionsView.rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// A working session's turn time, else how long ago the state began.
    private var trailing: String {
        if session.state == .working {
            return AgentElapsed.format(now.timeIntervalSince(session.turnStartedAt ?? session.since))
        }
        return Self.elapsed(since: session.since, now: now)
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
        case .asking: "Has a question — answer in \(session.source.displayName)"
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

/// Run times: "m:ss" under an hour, "h:mm:ss" from then on.
enum AgentElapsed {
    /// How many digits the run time has, which sets the wing's width:
    /// "m:ss", "mm:ss" or "h:mm:ss".
    enum WidthClass: Equatable {
        case short, medium, long

        init(seconds: TimeInterval) {
            switch max(0, seconds) {
            case ..<600: self = .short
            case ..<3600: self = .medium
            default: self = .long
            }
        }

        /// Compact content width that fits the widest time of this class.
        var width: CGFloat {
            switch self {
            case .short: IslandStyle.Size.compactElapsedShort
            case .medium: IslandStyle.Size.compactElapsedMedium
            case .long: IslandStyle.Size.compactElapsedLong
            }
        }

        /// Run time (seconds) at which the next class starts.
        var nextThreshold: TimeInterval? {
            switch self {
            case .short: 600
            case .medium: 3600
            case .long: nil
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
