//
//  AppDelegate.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    private let islandController: IslandController

    override init() {
        settings = AppSettings()
        islandController = IslandController(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        islandController.start()
    }
}
