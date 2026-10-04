//
//  ActivityCenter.swift
//  thenotch
//

import Foundation
import Observation

/// Something a module wants to show in the compact island.
struct LiveActivity: Equatable, Identifiable {
    let id: String
    let moduleID: String
    /// Higher wins (a timer about to finish outranks music).
    var priority: Int
    /// Removed automatically after this date; `nil` stays until removed.
    var expiresAt: Date?
    /// Opens the island on its module until it expires (a notification
    /// arriving) or, without expiry, until it's removed (a call ringing),
    /// instead of only showing beside the notch.
    var presents = false
}

/// Collects the modules' live activities and picks the one the compact
/// island shows.
@MainActor
@Observable
final class ActivityCenter {
    struct Entry: Equatable {
        var activity: LiveActivity
        /// Publish order; the most recent wins among equal priorities.
        var order: Int
    }

    /// The activity shown in compact mode, if any.
    private(set) var current: LiveActivity?

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var nextOrder = 0
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]
    /// Called for each published activity that `presents` (the island
    /// controller opens the island).
    @ObservationIgnored var onPresent: ((LiveActivity) -> Void)?
    /// Called with the id of each removed (or expired) activity.
    @ObservationIgnored var onRemove: ((String) -> Void)?

    /// Adds or replaces (by `id`) an activity.
    func publish(_ activity: LiveActivity) {
        entries[activity.id] = Entry(activity: activity, order: nextOrder)
        nextOrder += 1
        scheduleExpiry(for: activity)
        refresh()
        if activity.presents {
            onPresent?(activity)
        }
    }

    func remove(id: String) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        let removed = entries.removeValue(forKey: id) != nil
        refresh()
        if removed {
            onRemove?(id)
        }
    }

    /// Highest priority among unexpired activities; ties go to the most
    /// recently published.
    static func pick(_ entries: [Entry], now: Date) -> LiveActivity? {
        entries
            .filter { $0.activity.expiresAt.map { $0 > now } ?? true }
            .max { lhs, rhs in
                (lhs.activity.priority, lhs.order) < (rhs.activity.priority, rhs.order)
            }?
            .activity
    }

    private func refresh() {
        let picked = Self.pick(Array(entries.values), now: .now)
        if picked != current {
            current = picked
        }
    }

    private func scheduleExpiry(for activity: LiveActivity) {
        expiryTasks.removeValue(forKey: activity.id)?.cancel()
        guard let expiresAt = activity.expiresAt else { return }
        expiryTasks[activity.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(expiresAt.timeIntervalSinceNow, 0)))
            guard let self, !Task.isCancelled else { return }
            self.remove(id: activity.id)
        }
    }
}
