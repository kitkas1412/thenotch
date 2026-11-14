import Foundation
import Testing
@testable import thenotch

/// Pins the pre-rename literals so a rename is a deliberate change.
struct AppIdentityTests {
    @Test func pinsLiteralValues() {
        #expect(AppIdentity.name == "thenotch")
        #expect(AppIdentity.queuePrefix == "me.kitkas1412.thenotch")
        #expect(AppIdentity.hookSourcePrefix == "thenotch-source")
        #expect(AppIdentity.backupExtension == "thenotch-backup")
    }

    @Test func bundleIDInTestHostIsTheAppsBundleID() {
        #expect(AppIdentity.bundleID == "me.kitkas1412.thenotch")
        #expect(AppIdentity.logSubsystem == AppIdentity.bundleID)
    }

    @Test func queueLabelAppendsSuffixToPrefix() {
        #expect(AppIdentity.queueLabel("hooks") == "me.kitkas1412.thenotch.hooks")
    }

    @Test func supportDirectoryIsUnderApplicationSupport() {
        let url = AppIdentity.supportDirectory
        #expect(url.lastPathComponent == AppIdentity.bundleID)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    @Test func hookLinePrefixAndBackupSuffixMatchOldFormat() {
        #expect(AgentSource.linePrefix == "thenotch-source: ")
        let file = URL(fileURLWithPath: "/tmp/settings.json")
        #expect(file.appendingPathExtension(AppIdentity.backupExtension).lastPathComponent == "settings.json.thenotch-backup")
    }
}
