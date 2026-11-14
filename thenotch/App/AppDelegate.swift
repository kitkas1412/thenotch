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
    let updater: Updater
    private let toolHost: ToolHost

    override init() {
        settings = AppSettings()
        updater = Updater()
        toolHost = ToolHost(context: ToolContext(settings: settings))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        toolHost.start()
    }
}
