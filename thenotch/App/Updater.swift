//
//  Updater.swift
//  thenotch
//

import AppKit
import Observation
import Sparkle

/// Finds and installs new versions with Sparkle, from the appcast attached
/// to the latest GitHub release (`SUFeedURL` in `Config/Info.plist`).
/// Updates are verified with `SUPublicEDKey` before they're installed.
@MainActor
@Observable
final class Updater {
    /// False while a check or an update is already in progress.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        // Not in unit tests, which run inside the app: no network, no
        // permission prompt.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Checks now and shows the result, even when up to date.
    func checkForUpdates() {
        // An agent app isn't frontmost; bring Sparkle's window forward.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// Whether Sparkle checks once a day in the background: on by default
    /// (`SUEnableAutomaticChecks`, `SUScheduledCheckInterval` in
    /// `Config/Info.plist`); Settings can change it any time.
    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }
}
