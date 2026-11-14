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
    let hotKeys: HotKeyCenter
    private let toolHost: ToolHost

    override init() {
        settings = AppSettings()
        updater = Updater()
        hotKeys = HotKeyCenter()
        toolHost = ToolHost(context: ToolContext(settings: settings, hotKeys: hotKeys))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        toolHost.start()
    }
}
