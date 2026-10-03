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
        // LSUIElement apps have no Dock icon or app menu, so this menu is
        // the only way to reach Settings and to quit.
        MenuBarExtra("thenotch", systemImage: "capsule.fill") {
            MenuContent(updater: appDelegate.updater)
        }

        Settings {
            SettingsView(settings: appDelegate.settings, updater: appDelegate.updater)
        }
    }
}

private struct MenuContent: View {
    var updater: Updater

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            // An agent app isn't frontmost; bring the window forward.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Divider()

        Button("Quit thenotch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
