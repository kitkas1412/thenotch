//
//  thenotchApp.swift
//  thenotch
//
//  Created by Nguyễn Đình Đức on 3/10/26.
//

import SwiftUI

@main
struct thenotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement apps have no Dock icon or app menu, so this panel is
        // the only way to reach Settings and to quit.
        MenuBarExtra(AppIdentity.name, systemImage: "capsule.fill") {
            MenuPanel(sampler: appDelegate.systemMonitor, updater: appDelegate.updater, settings: appDelegate.settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: appDelegate.settings, updater: appDelegate.updater, hotKeys: appDelegate.hotKeys)
        }
    }
}
