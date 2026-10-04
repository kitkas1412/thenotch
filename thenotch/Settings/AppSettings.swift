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
        case .claudeCode: "Claude Code"
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
        case .claudeCode: "Shows when Claude Code is working, done, or waiting for your permission."
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
}
