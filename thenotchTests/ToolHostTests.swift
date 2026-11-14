import Testing
@testable import thenotch

@MainActor
private final class FakeTool: Tool {
    let id: String
    private let log: Log
    final class Log { var calls: [String] = [] }
    init(id: String, log: Log) { self.id = id; self.log = log }
    func start() { log.calls.append("start:\(id)") }
    func stop() { log.calls.append("stop:\(id)") }
}

@MainActor
struct ToolHostTests {
    @Test func toolKindIDsAreUniqueAndEqualRawValues() {
        let ids = ToolKind.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
        for kind in ToolKind.allCases { #expect(kind.id == kind.rawValue) }
        #expect(ToolKind.allCases == [.notch])
        #expect(ToolKind.notch.rawValue == "notch")
        #expect(ToolKind.notch.isOnByDefault)
    }

    @Test func buildsOneToolPerKindAtInitWithoutStartingThem() {
        let log = FakeTool.Log()
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
        let log = FakeTool.Log()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.start()
        #expect(host.runningIDs == ["notch"])
        host.stop()
        #expect(host.runningIDs.isEmpty)
        #expect(log.calls == ["start:notch", "stop:notch"])
    }

    @Test func startingTwiceStartsEachToolOnce() {
        let log = FakeTool.Log()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.start()
        host.start()
        #expect(log.calls == ["start:notch"])
    }

    @Test func stopWithoutStartDoesNothing() {
        let log = FakeTool.Log()
        let host = ToolHost(kinds: [.notch]) { FakeTool(id: $0.id, log: log) }
        host.stop()
        #expect(log.calls.isEmpty)
        #expect(host.runningIDs.isEmpty)
    }

    @Test func canRestartAfterStop() {
        let log = FakeTool.Log()
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
        let log = FakeTool.Log()
        let host = ToolHost(kinds: ToolKind.allCases) { FakeTool(id: $0.id, log: log) }
        host.start(); host.stop()
        let expectedStart = ToolKind.allCases.map { "start:\($0.id)" }
        let expectedStop = ToolKind.allCases.reversed().map { "stop:\($0.id)" }
        #expect(log.calls == expectedStart + expectedStop)
    }
}
