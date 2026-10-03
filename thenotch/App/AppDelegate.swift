//
//  AppDelegate.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let islandController = IslandController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        islandController.start()
    }
}
