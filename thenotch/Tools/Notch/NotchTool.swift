//
//  NotchTool.swift
//  thenotch
//

import Foundation

/// The island around the notch, as a tool.
@MainActor
final class NotchTool: Tool {
    let id = ToolKind.notch.id
    private let controller: IslandController
    private let settings: AppSettings
    private let hotKeys: HotKeyCenter

    init(settings: AppSettings, hotKeys: HotKeyCenter) {
        self.settings = settings
        self.hotKeys = hotKeys
        controller = IslandController(settings: settings)
    }

    func start() {
        controller.start()
        registerToggleShortcut()
        // For now this tool owns the callback; a router for several tools'
        // shortcuts will replace it.
        settings.onShortcutsChange = { [weak self] actionID in
            if actionID == ShortcutAction.notchToggle.id {
                self?.registerToggleShortcut()
            }
        }
    }

    func stop() {
        settings.onShortcutsChange = nil
        hotKeys.unregister(id: ShortcutAction.notchToggle.id)
        controller.stop()
    }

    private func registerToggleShortcut() {
        let actionID = ShortcutAction.notchToggle.id
        guard let shortcut = settings.shortcut(for: actionID) else {
            hotKeys.unregister(id: actionID)
            return
        }
        hotKeys.register(id: actionID, shortcut: shortcut) { [weak self] in
            self?.controller.toggleFromShortcut()
        }
    }
}
