//
//  NowPlayingModule.swift
//  thenotch
//

import SwiftUI

/// Shows what Spotify or Music is playing: artwork and a level meter beside
/// the notch while music plays, full controls when the island opens.
@MainActor
final class NowPlayingModule: IslandModule {
    let id = ModuleKind.nowPlaying.id
    /// Lowest priority: anything time-sensitive (timers, peeks) wins.
    static let priority = 10

    private let service = NowPlayingService()
    private let activities: ActivityCenter

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        service.onInfoChange = { [weak self] info in
            self?.updateActivity(info)
        }
        service.start()
    }

    func stop() {
        service.stop()
        service.onInfoChange = nil
        activities.remove(id: id)
    }

    func islandDidExpand() {
        service.refresh()
    }

    func compactLeading() -> AnyView {
        AnyView(CompactArtworkView(service: service))
    }

    func compactTrailing() -> AnyView {
        AnyView(LevelMeterView(service: service))
    }

    func expandedView() -> AnyView {
        AnyView(NowPlayingExpandedView(service: service))
    }

    /// The compact wings only show while music is playing; a paused track is
    /// still shown when the island is opened.
    private func updateActivity(_ info: NowPlayingInfo?) {
        if info?.isPlaying == true {
            activities.publish(LiveActivity(id: id, moduleID: id, priority: Self.priority))
        } else {
            activities.remove(id: id)
        }
    }
}
