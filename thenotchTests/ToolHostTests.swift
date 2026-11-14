import Foundation
import Testing
@testable import thenotch

@MainActor
private final class FakeTool: Tool {
    let id: String
    private let log: Calls
    final class Calls { var calls: [String] = [] }
    init(id: String, log: Calls) { self.id = id; self.log = log }
    func start() { log.calls.append("start:\(id)") }
    func stop() { log.calls.append("stop:\(id)") }
}

@MainActor
struct ToolHostTests {
    @Test func toolKindIDsAreUniqueAndEqualRawValues() {
        let ids = ToolKind.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
        for kind in ToolKind.allCases { #expect(kind.id == kind.rawValue) }
        #expect(ToolKind.allCases == [.notch, .systemMonitor, .windowManagement, .clipboard])
        #expect(ToolKind.notch.rawValue == "notch")
        #expect(ToolKind.notch.isOnByDefault)
        #expect(!ToolKind.systemMonitor.isOnByDefault)
    }

    @Test func buildsOneToolPerKindAtInitWithoutStartingThem() {
        let log = FakeTool.Calls()
        var made: [ToolKind] = []
        let host = ToolHost(kinds: [.notch]) { kind in
            made.append(kind)
            return FakeTool(id: kind.id, log: log)
        }
        #expect(made == [.notch])
        #expect(log.calls.isEmpty)
        #expect(host.runningIDs.isEmpty)
    }

    @Test func startThenStopTracksRunningIDs() {
        let log = FakeTool.Calls()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.start()
        #expect(host.runningIDs == ["notch"])
        host.stop()
        #expect(host.runningIDs.isEmpty)
        #expect(log.calls == ["start:notch", "stop:notch"])
    }

    @Test func startingTwiceStartsEachToolOnce() {
        let log = FakeTool.Calls()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.start()
        host.start()
        #expect(log.calls == ["start:notch"])
    }

    @Test func stopWithoutStartDoesNothing() {
        let log = FakeTool.Calls()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.stop()
        #expect(log.calls.isEmpty)
        #expect(host.runningIDs.isEmpty)
    }

    @Test func canRestartAfterStop() {
        let log = FakeTool.Calls()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.start(); host.stop(); host.start()
        #expect(log.calls == ["start:notch", "stop:notch", "start:notch"])
        #expect(host.runningIDs == ["notch"])
    }

    @Test func emptyKindsHostIsInert() {
        let host = ToolHost(kinds: []) { _ in Issue.record("make called"); fatalError() }
        host.start(); host.stop()
        #expect(host.runningIDs.isEmpty)
    }

    @Test func startsInOrderAndStopsInReverse() {
        // Only one ToolKind exists; use ids via a make that returns several tools is
        // not possible (one per kind), so ordering is verified with a duplicate-free
        // single kind here and the reverse order is covered once more kinds exist.
        let log = FakeTool.Calls()
        // Without settings only the tools on by default start.
        let kinds = ToolKind.allCases.filter(\.isOnByDefault)
        let host = ToolHost(kinds: kinds) { FakeTool(id: $0.id, log: log) }
        host.start(); host.stop()
        let expectedStart = kinds.map { "start:\($0.id)" }
        let expectedStop = kinds.reversed().map { "stop:\($0.id)" }
        #expect(log.calls == expectedStart + expectedStop)
    }

    // MARK: With settings

    private func makeSettings(_ toolEnabled: Bool? = nil) -> AppSettings {
        let suite = "thenotchTests.ToolHost.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        if let toolEnabled { settings.setToolEnabled(.notch, toolEnabled) }
        return settings
    }

    @Test func initWithSettingsInstallsChangeHandler() {
        let settings = makeSettings()
        #expect(settings.onToolsChange == nil)
        _ = ToolHost(kinds: [.notch], settings: settings) { FakeTool(id: $0.id, log: FakeTool.Calls()) }
        #expect(settings.onToolsChange != nil)
    }

    @Test func startSkipsDisabledTools() {
        let calls = FakeTool.Calls()
        let host = ToolHost(kinds: [.notch], settings: makeSettings(false)) { FakeTool(id: $0.id, log: calls) }
        host.start()
        #expect(calls.calls.isEmpty)
        #expect(host.runningIDs.isEmpty)
    }

    @Test func enablingWhileStartedStartsTheTool() {
        let calls = FakeTool.Calls()
        let settings = makeSettings(false)
        let host = ToolHost(kinds: [.notch], settings: settings) { FakeTool(id: $0.id, log: calls) }
        host.start()
        settings.setToolEnabled(.notch, true)
        #expect(calls.calls == ["start:notch"])
        #expect(host.runningIDs == ["notch"])
    }

    @Test func disablingWhileStartedStopsTheTool() {
        let calls = FakeTool.Calls()
        let settings = makeSettings()
        let host = ToolHost(kinds: [.notch], settings: settings) { FakeTool(id: $0.id, log: calls) }
        host.start()
        #expect(host.runningIDs == ["notch"])
        settings.setToolEnabled(.notch, false)
        #expect(calls.calls == ["start:notch", "stop:notch"])
        #expect(host.runningIDs.isEmpty)
    }

    @Test func togglingBeforeStartOrAfterStopDoesNothing() {
        let calls = FakeTool.Calls()
        let settings = makeSettings()
        let host = ToolHost(kinds: [.notch], settings: settings) { FakeTool(id: $0.id, log: calls) }
        settings.setToolEnabled(.notch, false)
        settings.setToolEnabled(.notch, true)
        #expect(calls.calls.isEmpty)
        host.start()
        host.stop()
        calls.calls.removeAll()
        settings.setToolEnabled(.notch, false)
        settings.setToolEnabled(.notch, true)
        #expect(calls.calls.isEmpty)
        #expect(host.runningIDs.isEmpty)
    }

    @Test func settingToTheSameValueDoesNotRestartTheTool() {
        let calls = FakeTool.Calls()
        let settings = makeSettings()
        let host = ToolHost(kinds: [.notch], settings: settings) { FakeTool(id: $0.id, log: calls) }
        host.start()
        settings.setToolEnabled(.notch, true)
        #expect(calls.calls == ["start:notch"])
    }
}
