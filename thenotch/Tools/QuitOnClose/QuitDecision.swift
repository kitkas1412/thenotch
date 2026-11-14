//
//  QuitDecision.swift
//  thenotch
//

import Foundation

/// Whether an app whose window closed should quit. Every condition must
/// hold; a missed quit is fine, a false one is not.
enum QuitDecision: Equatable {
    case quit
    case skip(SkipReason)

    enum SkipReason: Equatable {
        case windowsUnreadable
        case hasWindow
        case windowListUnavailable
        case hasVisibleWindow
        case notRunning
        case notFinishedLaunching
        case hidden
        case notRegular
        case notFrontmost
        case noBundleID
        case neverQuits
        case notAllowed
    }

    /// Plain values read just before deciding.
    struct Input {
        /// Subroles of the app's AX windows (`nil` for one without a subrole);
        /// `nil` when the list couldn't be read.
        var axSubroles: [String?]?
        /// Windows on screen or not; `nil` when the list couldn't be read.
        var cgWindows: [WindowInventory.CGWindow]?
        var pid: pid_t
        var isRunning = true
        var finishedLaunching = true
        var isHidden = false
        var isRegular = true
        var isFrontmost = true
        var bundleID: String?
        var mode: QuitOnCloseMode = .allExceptListed
        var listedApps: [String] = []
        var ownBundleID: String = AppIdentity.bundleID
    }

    /// Apps that must never be quit.
    static let neverQuit: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
    ]

    static func decide(_ input: Input) -> QuitDecision {
        guard let subroles = input.axSubroles else { return .skip(.windowsUnreadable) }
        if subroles.contains(where: WindowInventory.isRealWindow(subrole:)) { return .skip(.hasWindow) }
        guard let cgWindows = input.cgWindows else { return .skip(.windowListUnavailable) }
        if WindowInventory.hasVisibleWindow(cgWindows, pid: input.pid) { return .skip(.hasVisibleWindow) }
        guard input.isRunning else { return .skip(.notRunning) }
        guard input.finishedLaunching else { return .skip(.notFinishedLaunching) }
        guard !input.isHidden else { return .skip(.hidden) }
        guard input.isRegular else { return .skip(.notRegular) }
        guard input.isFrontmost else { return .skip(.notFrontmost) }
        guard let bundleID = input.bundleID else { return .skip(.noBundleID) }
        guard !neverQuit.contains(bundleID), bundleID != input.ownBundleID else { return .skip(.neverQuits) }
        let isListed = input.listedApps.contains(bundleID)
        switch input.mode {
        case .allExceptListed: if isListed { return .skip(.notAllowed) }
        case .onlyListed: if !isListed { return .skip(.notAllowed) }
        }
        return .quit
    }
}
