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
        // LSUIElement apps have no Dock icon or app menu, so this is the only way to quit.
        MenuBarExtra("thenotch", systemImage: "capsule.fill") {
            Button("Quit thenotch") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
