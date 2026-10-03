//
//  ActivityCenterTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

@MainActor
struct ActivityCenterTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    func entry(_ id: String, priority: Int, order: Int, expiresIn: TimeInterval? = nil) -> ActivityCenter.Entry {
        ActivityCenter.Entry(
            activity: LiveActivity(
                id: id,
                moduleID: id,
                priority: priority,
                expiresAt: expiresIn.map { now.addingTimeInterval($0) }
            ),
            order: order
        )
    }

    @Test func pickReturnsNilWhenEmpty() {
        #expect(ActivityCenter.pick([], now: now) == nil)
    }

    @Test func pickPrefersHigherPriority() {
        let picked = ActivityCenter.pick(
            [entry("music", priority: 10, order: 1), entry("timer", priority: 50, order: 0)],
            now: now
        )
        #expect(picked?.id == "timer")
    }

    @Test func pickPrefersMostRecentOnTie() {
        let picked = ActivityCenter.pick(
            [entry("a", priority: 10, order: 0), entry("b", priority: 10, order: 1)],
            now: now
        )
        #expect(picked?.id == "b")
    }

    @Test func pickSkipsExpiredActivities() {
        let picked = ActivityCenter.pick(
            [entry("peek", priority: 90, order: 1, expiresIn: -1), entry("music", priority: 10, order: 0)],
            now: now
        )
        #expect(picked?.id == "music")
    }

    @Test func pickKeepsUnexpiredActivities() {
        let picked = ActivityCenter.pick([entry("peek", priority: 90, order: 0, expiresIn: 2)], now: now)
        #expect(picked?.id == "peek")
    }

    @Test func publishAndRemoveUpdateCurrent() {
        let center = ActivityCenter()
        center.publish(LiveActivity(id: "music", moduleID: "nowPlaying", priority: 10))
        #expect(center.current?.id == "music")

        center.publish(LiveActivity(id: "timer", moduleID: "timer", priority: 50))
        #expect(center.current?.id == "timer")

        center.remove(id: "timer")
        #expect(center.current?.id == "music")

        center.remove(id: "music")
        #expect(center.current == nil)
    }

    @Test func publishingSameIDReplacesActivity() {
        let center = ActivityCenter()
        center.publish(LiveActivity(id: "music", moduleID: "nowPlaying", priority: 10))
        center.publish(LiveActivity(id: "music", moduleID: "nowPlaying", priority: 20))
        #expect(center.current?.priority == 20)
        center.remove(id: "music")
        #expect(center.current == nil)
    }

    @Test func expiredActivityIsRemovedAutomatically() async throws {
        let center = ActivityCenter()
        center.publish(LiveActivity(id: "peek", moduleID: "battery", priority: 90, expiresAt: .now.addingTimeInterval(0.05)))
        #expect(center.current?.id == "peek")
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == nil)
    }
}
