//
//  Shortcut.swift
//  thenotch
//

import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a Carbon virtual key code and modifiers.
/// Pure values, so everything here is testable.
struct Shortcut: Codable, Hashable, Sendable {
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt8

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        /// The modifiers of an event; Caps Lock, Fn etc. are ignored.
        init(_ flags: NSEvent.ModifierFlags) {
            var result: Modifiers = []
            if flags.contains(.command) { result.insert(.command) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.control) { result.insert(.control) }
            if flags.contains(.shift) { result.insert(.shift) }
            self = result
        }

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// Flags for `RegisterEventHotKey`.
        var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.command) { flags |= UInt32(cmdKey) }
            if contains(.option) { flags |= UInt32(optionKey) }
            if contains(.control) { flags |= UInt32(controlKey) }
            if contains(.shift) { flags |= UInt32(shiftKey) }
            return flags
        }
    }

    enum Validation: Equatable, Sendable {
        case valid
        /// Without ⌘ or ⌃ (and not a function key) it would fire while typing.
        case needsCommandOrControl
        /// A macOS shortcut, named.
        case reservedBySystem(String)
    }

    let keyCode: UInt32
    let modifiers: Modifiers

    init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.init(keyCode: UInt32(keyCode), modifiers: Modifiers(flags))
    }

    var carbonModifiers: UInt32 { modifiers.carbonFlags }

    var isFunctionKey: Bool { Self.functionKeys[keyCode] != nil }

    var validation: Validation {
        if let name = Self.reserved[Self.Combo(keyCode: keyCode, modifiers: modifiers)] {
            return .reservedBySystem(name)
        }
        if isFunctionKey { return .valid }
        if modifiers.contains(.command) || modifiers.contains(.control) { return .valid }
        return .needsCommandOrControl
    }

    /// In macOS order (⌃⌥⇧⌘) followed by the key, e.g. "⌃⌥Space".
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        names[keyCode] ?? functionKeys[keyCode] ?? "Key \(keyCode)"
    }

    // MARK: Tables

    private struct Combo: Hashable {
        let keyCode: UInt32
        let modifiers: Modifiers
    }

    private static let reserved: [Combo: String] = {
        func combo(_ key: Int, _ modifiers: Modifiers) -> Combo {
            Combo(keyCode: UInt32(key), modifiers: modifiers)
        }
        return [
            combo(kVK_Space, .command): "Spotlight",
            combo(kVK_Space, .control): "Input sources",
            combo(kVK_Tab, .command): "App switcher",
            combo(kVK_ANSI_Grave, .command): "Window switcher",
            combo(kVK_ANSI_Q, .command): "Quit",
            combo(kVK_ANSI_W, .command): "Close window",
            combo(kVK_ANSI_H, .command): "Hide app",
            combo(kVK_ANSI_M, .command): "Minimize",
            combo(kVK_ANSI_Comma, .command): "Settings",
            combo(kVK_ANSI_3, [.command, .shift]): "Screenshot",
            combo(kVK_ANSI_4, [.command, .shift]): "Screenshot",
            combo(kVK_ANSI_5, [.command, .shift]): "Screenshot",
            combo(kVK_UpArrow, .control): "Mission Control",
            combo(kVK_DownArrow, .control): "Application windows",
            combo(kVK_LeftArrow, .control): "Move to the left Space",
            combo(kVK_RightArrow, .control): "Move to the right Space",
        ]
    }()

    private static let names: [UInt32: String] = {
        let table: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Quote: "'", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/",
            kVK_ANSI_Period: ".", kVK_ANSI_Grave: "`",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        return Dictionary(uniqueKeysWithValues: table.map { (UInt32($0.key), $0.value) })
    }()

    private static let functionKeys: [UInt32: String] = {
        let table: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        return Dictionary(uniqueKeysWithValues: table.map { (UInt32($0.key), $0.value) })
    }()
}

/// An action a shortcut can trigger.
struct ShortcutAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let tool: ToolKind
    /// Used until the user records or clears the shortcut.
    let defaultShortcut: Shortcut?

    init(id: String, title: String, tool: ToolKind, defaultShortcut: Shortcut? = nil) {
        self.id = id
        self.title = title
        self.tool = tool
        self.defaultShortcut = defaultShortcut
    }

    static let notchToggle = ShortcutAction(
        id: "notch.toggle", title: "Open or close the island", tool: .notch)

    /// Id of the shortcut that runs a window action.
    static func windowActionID(_ action: WindowAction) -> String {
        "windows.\(action.rawValue)"
    }

    /// One action per `WindowAction`, with its default shortcut.
    static let windowActions: [ShortcutAction] = WindowAction.allCases.map { action in
        ShortcutAction(
            id: windowActionID(action),
            title: action.title,
            tool: .windowManagement,
            defaultShortcut: action.defaultShortcut)
    }

    /// Every action with a shortcut setting.
    static let all: [ShortcutAction] = [notchToggle] + windowActions

    /// The actions of one tool, in display order.
    static func actions(for tool: ToolKind) -> [ShortcutAction] {
        all.filter { $0.tool == tool }
    }
}
