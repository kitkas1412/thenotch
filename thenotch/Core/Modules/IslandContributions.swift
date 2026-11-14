//
//  IslandContributions.swift
//  thenotch
//

import Observation

/// A module that a tool (not a `ModuleKind`) adds to the island, shown after
/// the built-in modules while the Notch tool runs. The island attaches it
/// when it starts (or when it is added meanwhile) and detaches it when the
/// island stops or the module is removed; the island never calls
/// `start()`/`stop()`/`suspend()` on it, the owning tool does.
@MainActor
protocol ContributedIslandModule: IslandModule {
    /// The island is up: publish activities to `activities` from now on.
    func attach(activities: ActivityCenter)
    /// The island is going away or the module was removed: withdraw activities.
    func detach()
}

/// What the island offers a contributed module's tool.
@MainActor
protocol IslandHosting: AnyObject {
    /// Shortcut semantics: opens the island on the module, selects it if the
    /// island shows another one, or closes the island if it shows it. Returns
    /// whether anything happened.
    func toggleContribution(id: String) -> Bool
    func closeIsland()
}

/// Registry between tools and the island: a tool adds its module, and the
/// island (the host, while the Notch tool runs) shows it and answers shortcuts.
@MainActor
@Observable
final class IslandContributions {
    private(set) var modules: [any ContributedIslandModule] = []
    /// The island is running and can show contributions; observable, so a
    /// tool can fall back to its own window while it is false.
    private(set) var isHostAvailable = false

    /// Set by the controller while it runs.
    @ObservationIgnored weak var host: (any IslandHosting)? {
        didSet { isHostAvailable = host != nil }
    }

    /// Adds `module`, replacing one with the same id.
    func add(_ module: any ContributedIslandModule) {
        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            modules[index] = module
        } else {
            modules.append(module)
        }
    }

    func remove(id: String) {
        modules.removeAll { $0.id == id }
    }

    /// Opens, selects or closes as `IslandHosting.toggleContribution(id:)`.
    /// False without a host (the Notch tool is off).
    func show(_ id: String) -> Bool {
        host?.toggleContribution(id: id) ?? false
    }

    /// Closes the island.
    func close() {
        host?.closeIsland()
    }
}

/// What a shortcut for a contributed module does, from plain values.
enum ContributionToggle: Equatable {
    case none, open, select, close

    static func decide(
        isStarted: Bool,
        hasModule: Bool,
        isExpanded: Bool,
        shownModuleID: String?,
        targetID: String,
        isVisible: Bool,
        isBlocked: Bool
    ) -> ContributionToggle {
        guard isStarted, hasModule else { return .none }
        if isExpanded, shownModuleID == targetID { return .close }
        guard isVisible, !isBlocked else { return .none }
        return isExpanded ? .select : .open
    }
}

/// What the island does with the keyboard and with screen-capture exclusion
/// for the shown module, from plain values.
enum ShownModulePolicy {
    enum KeyAction: Equatable { case take, release }
    enum SharingAction: Equatable {
        /// Hide the window from capture and drop any pending restore.
        case exclude
        /// Make the window capturable now and drop any pending restore
        /// (the island reopened on another module within the delay).
        case restoreNow
        /// Capturable again after a delay (the island is closed).
        case scheduleRestore
        /// Nothing to change.
        case keep
    }

    /// Exclusion lasts for the whole opening and a moment after the island
    /// closes: switching tabs while open never restores capture.
    static func decide(
        isExpanded: Bool,
        shownTakesKeyboard: Bool,
        shownExcludesCapture: Bool,
        currentlyExcluding: Bool,
        hasRestoreTask: Bool
    ) -> (key: KeyAction, sharing: SharingAction) {
        let key: KeyAction = isExpanded && shownTakesKeyboard ? .take : .release
        let sharing: SharingAction
        if isExpanded {
            if shownExcludesCapture {
                sharing = .exclude
            } else {
                sharing = hasRestoreTask ? .restoreNow : .keep
            }
        } else {
            sharing = currentlyExcluding && !hasRestoreTask ? .scheduleRestore : .keep
        }
        return (key, sharing)
    }
}

/// What a new presentation (a banner, a call) does to the island.
enum PresentationPolicy {
    enum Action: Equatable { case ignore, open, select }

    /// An island showing a module that takes the keyboard is never switched
    /// away: keystrokes would land in the app that was in front before.
    static func decide(isExpanded: Bool, hasPresentation: Bool, shownTakesKeyboard: Bool) -> Action {
        guard isExpanded else { return .open }
        guard hasPresentation, !shownTakesKeyboard else { return .ignore }
        return .select
    }
}
