//
//  AmbientConditions.swift
//  thenotch
//

/// What the system is doing that decides whether the island may run
/// ambient animation (the level meter): nobody sees it while the display
/// sleeps, the screen is locked or another user's session is in front, and
/// Low Power Mode asks apps to save energy.
struct AmbientConditions: Equatable {
    var isDisplayAsleep = false
    var isScreenLocked = false
    /// Fast user switching: another user's session is in front.
    var isSessionInactive = false
    var isLowPowerMode = false

    var allowsAnimation: Bool {
        !(isDisplayAsleep || isScreenLocked || isSessionInactive || isLowPowerMode)
    }
}
