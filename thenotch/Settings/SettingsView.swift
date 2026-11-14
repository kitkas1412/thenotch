//
//  SettingsView.swift
//  thenotch
//

import SwiftUI

/// The settings window: a sidebar with General and one entry per tool, and
/// the chosen pane beside it. Opens on the pane used last.
struct SettingsView: View {
    var settings: AppSettings
    var updater: Updater

    @AppStorage("settings.pane") private var storedPane = SettingsPane.general.storedValue

    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { SettingsPane(storedValue: storedPane) },
            set: { storedPane = ($0 ?? .general).storedValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Label {
                    Text("General")
                } icon: {
                    SettingsIconTile(symbol: "gearshape.fill", tint: .gray)
                }
                .tag(SettingsPane.general)

                Section("Tools") {
                    ForEach(ToolKind.allCases) { kind in
                        Label {
                            Text(kind.title)
                        } icon: {
                            SettingsIconTile(symbol: kind.symbol, tint: kind.tint)
                        }
                        .tag(SettingsPane.tool(kind))
                    }
                }
            }
            .navigationSplitViewColumnWidth(SettingsLayout.sidebarWidth)
        } detail: {
            switch SettingsPane(storedValue: storedPane) {
            case .general:
                GeneralPane(settings: settings, updater: updater)
                    .navigationTitle("General")
            case .tool(.notch):
                NotchPane(settings: settings)
                    .navigationTitle(ToolKind.notch.title)
            }
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
    }
}

enum SettingsLayout {
    static let width: CGFloat = 720
    static let height: CGFloat = 560
    static let sidebarWidth: CGFloat = 190
    /// Side of an icon tile, like the rows of System Settings.
    static let iconTile: CGFloat = 22
}
