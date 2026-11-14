import Foundation

/// The app's name and bundle-identity strings, in one place.
enum AppIdentity {
    /// Shown to the user.
    static let name = "thenotch"
    /// The bundle identifier, or the name when running without a bundle.
    static var bundleID: String { Bundle.main.bundleIdentifier ?? name }
    /// Reverse-DNS prefix of queue labels.
    static let queuePrefix = "me.kitkas1412.thenotch"
    /// Unified-logging subsystem.
    static var logSubsystem: String { bundleID }
    /// `~/Library/Application Support/<bundle id>`.
    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent(bundleID, isDirectory: true)
    }
    /// First line of a hook command's payload: `<prefix>: <source>`.
    static let hookSourcePrefix = "thenotch-source"
    /// Extension of the copy of a hooks file made before editing it.
    static let backupExtension = "thenotch-backup"

    static func queueLabel(_ suffix: String) -> String { "\(queuePrefix).\(suffix)" }
}
