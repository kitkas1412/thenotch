//
//  AppSettings.swift
//  thenotch
//

import Foundation
import Observation
import ServiceManagement

/// Modules the user can switch on and off. `rawValue` is the module's `id`.
enum ModuleKind: String, CaseIterable, Identifiable {
    case nowPlaying
    case battery
    case shelf
    case hud
    case bluetooth
    case notifications
    case claudeCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .battery: "Battery"
        case .shelf: "Shelf"
        case .hud: "Volume & Brightness"
        case .bluetooth: "Bluetooth"
        case .notifications: "Notifications"
        case .claudeCode: "AI Agents"
        }
    }

    /// SF Symbol for the module's tab in the open island.
    var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .battery: "battery.100percent"
        case .shelf: "tray.full.fill"
        case .hud: "speaker.wave.2.fill"
        case .bluetooth: "airpods"
        case .notifications: "bell.badge.fill"
        case .claudeCode: "sparkle"
        }
    }

    var summary: String {
        switch self {
        case .nowPlaying: "Track, artwork and controls for Spotify and Music."
        case .battery: "Shows the battery when you plug in, unplug, or run low."
        case .shelf: "Drag files onto the notch to keep them at hand."
        case .hud: "Shows volume and brightness at the notch instead of the macOS overlay."
        case .bluetooth: "Shows AirPods and other Bluetooth devices, with their battery, when they connect."
        case .notifications: "Shows notifications at the notch instead of the macOS banners."
        case .claudeCode: "Shows when Claude Code or Codex is working, done, or waiting for you."
        }
    }

    /// Whether the module is on until the user decides. Volume &
    /// Brightness and Notifications need Accessibility access and Bluetooth
    /// needs Bluetooth access, asked for when they're turned on; Claude Code
    /// adds hooks to Claude Code's settings.
    var isOnByDefault: Bool {
        self != .hud && self != .bluetooth && self != .notifications && self != .claudeCode
    }

    /// Whether the module needs Accessibility access.
    var needsAccessibility: Bool {
        self == .hud || self == .notifications
    }

    @MainActor
    func makeModule(activities: ActivityCenter, settings: AppSettings) -> any IslandModule {
        switch self {
        case .nowPlaying: NowPlayingModule(activities: activities)
        case .battery: BatteryModule(activities: activities)
        case .shelf: ShelfModule(activities: activities, settings: settings)
        case .hud: HUDModule(activities: activities)
        case .bluetooth: BluetoothModule(activities: activities)
        case .notifications: NotificationsModule(activities: activities)
        case .claudeCode: ClaudeCodeModule(activities: activities)
        }
    }
}

/// How long files stay on the shelf.
enum ShelfLifetime: String, CaseIterable, Identifiable {
    case hour, day, week, forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: "1 hour"
        case .day: "1 day"
        case .week: "1 week"
        case .forever: "Until removed"
        }
    }

    /// `nil` keeps files until the user removes them.
    var interval: TimeInterval? {
        switch self {
        case .hour: 60 * 60
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .forever: nil
        }
    }
}

/// User preferences, persisted in `UserDefaults` (launch at login is owned
/// by the system via `SMAppService`).
@MainActor
@Observable
final class AppSettings {
    /// Enabled modules, in `ModuleKind.allCases` order.
    private(set) var enabledModules: [ModuleKind]
    /// Called after a module is switched on or off.
    @ObservationIgnored var onModulesChange: (() -> Void)?
    /// Enabled tools, in `ToolKind.allCases` order.
    private(set) var enabledTools: [ToolKind]
    /// Called after a tool is switched on or off.
    @ObservationIgnored var onToolsChange: (() -> Void)?

    /// Effective global shortcuts by action id (`ShortcutAction.id`): the
    /// user's, or the action's default until they record or clear one. Only
    /// the bound ones.
    private(set) var shortcuts: [String: Shortcut]
    /// Actions whose shortcut the user cleared (stored as JSON `null`), so
    /// the default doesn't come back.
    @ObservationIgnored private var clearedShortcuts: Set<String> = []
    @ObservationIgnored private var shortcutObservations: [WeakShortcutObservation] = []

    var shelfLifetime: ShelfLifetime {
        didSet { defaults.set(shelfLifetime.rawValue, forKey: Self.shelfLifetimeKey) }
    }

    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    private(set) var launchAtLoginError: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabledModules = ModuleKind.allCases.filter {
            defaults.object(forKey: Self.key(for: $0)) as? Bool ?? $0.isOnByDefault
        }
        enabledTools = ToolKind.allCases.filter {
            defaults.object(forKey: Self.key(for: $0)) as? Bool ?? $0.isOnByDefault
        }
        var shortcuts: [String: Shortcut] = [:]
        var cleared: Set<String> = []
        for action in ShortcutAction.all {
            let data = defaults.data(forKey: Self.shortcutKey(for: action.id))
            if let data, data == Self.clearedMarker {
                cleared.insert(action.id)
            } else if let shortcut = data.flatMap({ try? JSONDecoder().decode(Shortcut.self, from: $0) }) {
                shortcuts[action.id] = shortcut
            } else if let shortcut = action.defaultShortcut {
                shortcuts[action.id] = shortcut
            }
        }
        self.shortcuts = shortcuts
        clearedShortcuts = cleared
        shelfLifetime = defaults.string(forKey: Self.shelfLifetimeKey).flatMap(ShelfLifetime.init) ?? .day
    }

    func isEnabled(_ kind: ModuleKind) -> Bool {
        enabledModules.contains(kind)
    }

    func setEnabled(_ kind: ModuleKind, _ enabled: Bool) {
        guard enabled != isEnabled(kind) else { return }
        defaults.set(enabled, forKey: Self.key(for: kind))
        enabledModules = ModuleKind.allCases.filter { $0 == kind ? enabled : isEnabled($0) }
        onModulesChange?()
    }

    func isToolEnabled(_ kind: ToolKind) -> Bool {
        enabledTools.contains(kind)
    }

    func setToolEnabled(_ kind: ToolKind, _ enabled: Bool) {
        guard enabled != isToolEnabled(kind) else { return }
        defaults.set(enabled, forKey: Self.key(for: kind))
        enabledTools = ToolKind.allCases.filter { $0 == kind ? enabled : isToolEnabled($0) }
        onToolsChange?()
    }

    // MARK: Shortcuts

    /// The user's shortcut, the default if they haven't touched it, `nil`
    /// if unbound or cleared.
    func shortcut(for actionID: String) -> Shortcut? {
        shortcuts[actionID]
    }

    /// Binds the action; `nil` clears it (the default doesn't come back, see
    /// `resetShortcut(for:)`).
    func setShortcut(_ shortcut: Shortcut?, for actionID: String) {
        let defaultShortcut = Self.defaultShortcut(for: actionID)
        let isCleared = shortcut == nil && defaultShortcut != nil
        guard shortcut != shortcuts[actionID] || isCleared != clearedShortcuts.contains(actionID) else { return }
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Self.shortcutKey(for: actionID))
            clearedShortcuts.remove(actionID)
        } else if defaultShortcut != nil {
            defaults.set(Self.clearedMarker, forKey: Self.shortcutKey(for: actionID))
            clearedShortcuts.insert(actionID)
        } else {
            defaults.removeObject(forKey: Self.shortcutKey(for: actionID))
            clearedShortcuts.remove(actionID)
        }
        shortcuts[actionID] = shortcut
        notifyShortcutChange(actionID)
    }

    /// Back to the action's default shortcut (none for actions without one).
    func resetShortcut(for actionID: String) {
        let defaultShortcut = Self.defaultShortcut(for: actionID)
        let wasStored = defaults.object(forKey: Self.shortcutKey(for: actionID)) != nil
        guard wasStored || shortcuts[actionID] != defaultShortcut else { return }
        defaults.removeObject(forKey: Self.shortcutKey(for: actionID))
        clearedShortcuts.remove(actionID)
        let changed = shortcuts[actionID] != defaultShortcut
        shortcuts[actionID] = defaultShortcut
        if changed { notifyShortcutChange(actionID) }
    }

    /// Calls `handler` with the action id after its shortcut really changed,
    /// until the returned token is cancelled or released.
    func observeShortcuts(_ handler: @escaping (String) -> Void) -> ShortcutObservation {
        let observation = ShortcutObservation(handler: handler)
        shortcutObservations.removeAll { $0.value == nil }
        shortcutObservations.append(WeakShortcutObservation(observation))
        return observation
    }

    private func notifyShortcutChange(_ actionID: String) {
        shortcutObservations.removeAll { $0.value == nil }
        for box in shortcutObservations {
            box.value?.fire(actionID)
        }
    }

    private static let clearedMarker = Data("null".utf8)

    private static func defaultShortcut(for actionID: String) -> Shortcut? {
        ShortcutAction.all.first { $0.id == actionID }?.defaultShortcut
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        launchAtLoginStatus == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    /// The user can change it in System Settings › Login Items at any time.
    func refreshLaunchAtLogin() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    private static let shelfLifetimeKey = "shelf.lifetime"

    private static func key(for kind: ModuleKind) -> String {
        "module.\(kind.rawValue).enabled"
    }

    private static func shortcutKey(for actionID: String) -> String {
        "shortcut.\(actionID)"
    }

    private static func key(for kind: ToolKind) -> String {
        "tool.\(kind.rawValue).enabled"
    }
}

/// Token for `AppSettings.observeShortcuts`; keep it while observing.
@MainActor
final class ShortcutObservation {
    private var handler: ((String) -> Void)?

    fileprivate init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    func cancel() {
        handler = nil
    }

    fileprivate func fire(_ actionID: String) {
        handler?(actionID)
    }
}

@MainActor
private struct WeakShortcutObservation {
    weak var value: ShortcutObservation?

    init(_ value: ShortcutObservation) {
        self.value = value
    }
}
