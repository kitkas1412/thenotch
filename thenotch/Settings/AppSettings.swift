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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .battery: "Battery"
        }
    }

    var summary: String {
        switch self {
        case .nowPlaying: "Track, artwork and controls for Spotify and Music."
        case .battery: "Shows the battery when you plug in, unplug, or run low."
        }
    }

    @MainActor
    func makeModule(activities: ActivityCenter) -> any IslandModule {
        switch self {
        case .nowPlaying: NowPlayingModule(activities: activities)
        case .battery: BatteryModule(activities: activities)
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

    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    private(set) var launchAtLoginError: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Every module is on until the user turns it off.
        enabledModules = ModuleKind.allCases.filter {
            defaults.object(forKey: Self.key(for: $0)) as? Bool ?? true
        }
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

    private static func key(for kind: ModuleKind) -> String {
        "module.\(kind.rawValue).enabled"
    }
}
