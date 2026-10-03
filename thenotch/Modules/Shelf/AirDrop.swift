//
//  AirDrop.swift
//  thenotch
//

import AppKit

/// Sends files with AirDrop through the system sharing service.
@MainActor
enum AirDrop {
    /// Kept alive while its window is up.
    private static var service: NSSharingService?

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else { return }
        self.service = service
        // Without a Dock icon the app is never active; the AirDrop window
        // would open behind the frontmost app.
        NSApp.activate()
        service.perform(withItems: urls)
    }
}
