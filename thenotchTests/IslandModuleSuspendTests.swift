import SwiftUI
import Testing
@testable import thenotch

@MainActor
private final class DefaultSuspendModule: IslandModule {
    let id = "fake"
    var events: [String] = []
    func start() { events.append("start") }
    func stop() { events.append("stop") }
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
    var hasExpandedContent: Bool { false }
}

@MainActor
private final class CustomSuspendModule: IslandModule {
    let id = "custom"
    var events: [String] = []
    func start() { events.append("start") }
    func stop() { events.append("stop") }
    func suspend() { events.append("suspend") }
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
    var hasExpandedContent: Bool { false }
}

@MainActor
struct IslandModuleSuspendTests {
    @Test func suspendDefaultsToStop() {
        let module = DefaultSuspendModule()
        module.suspend()
        #expect(module.events == ["stop"])
    }

    @Test func overriddenSuspendDoesNotCallStop() {
        let module = CustomSuspendModule()
        let asProtocol: any IslandModule = module
        asProtocol.suspend()
        #expect(module.events == ["suspend"])
    }
}
