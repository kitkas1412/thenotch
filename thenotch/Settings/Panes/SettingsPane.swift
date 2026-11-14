//
//  SettingsPane.swift
//  thenotch
//

/// A sidebar entry of the settings window. Stored in
/// `@AppStorage("settings.pane")` as "general" or "tool.<ToolKind.rawValue>".
/// The legacy value "modules" (the old Modules tab) maps to the Notch tool;
/// anything unknown falls back to General.
enum SettingsPane: Hashable {
    case general
    case tool(ToolKind)

    static let toolPrefix = "tool."

    init(storedValue: String) {
        if storedValue == "modules" {
            self = .tool(.notch)
        } else if storedValue.hasPrefix(Self.toolPrefix),
                  let kind = ToolKind(rawValue: String(storedValue.dropFirst(Self.toolPrefix.count))) {
            self = .tool(kind)
        } else {
            self = .general
        }
    }

    var storedValue: String {
        switch self {
        case .general: "general"
        case .tool(let kind): Self.toolPrefix + kind.rawValue
        }
    }
}
