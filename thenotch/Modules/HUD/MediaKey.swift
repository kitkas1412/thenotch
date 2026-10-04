//
//  MediaKey.swift
//  thenotch
//

import Foundation

/// The volume and brightness keys, read from the events an event tap sees.
/// Pure values so the parsing can be unit tested.
enum MediaKey: Equatable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    struct Press: Equatable {
        let key: MediaKey
        let isDown: Bool
        let isRepeat: Bool
    }

    /// `NSEvent.EventSubtype` of special keys in a `.systemDefined` event
    /// (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`).
    static let auxControlButtons = 8

    /// A special key from a `.systemDefined` event: `data1` holds the key
    /// (`NX_KEYTYPE_*`) in its high 16 bits, then its state (0xA down, 0xB
    /// up) and a repeat bit.
    static func press(subtype: Int, data1: Int) -> Press? {
        guard subtype == auxControlButtons else { return nil }
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard state == 0xA || state == 0xB else { return nil }
        let key: MediaKey
        switch keyType {
        case 0: key = .volumeUp  // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown  // NX_KEYTYPE_SOUND_DOWN
        case 2: key = .brightnessUp  // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown  // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 7: key = .mute  // NX_KEYTYPE_MUTE
        default: return nil
        }
        return Press(key: key, isDown: state == 0xA, isRepeat: flags & 0x1 != 0)
    }

    /// Some Apple keyboards send the brightness keys as ordinary key
    /// events, with these key codes.
    static func brightnessKey(keyCode: Int64) -> MediaKey? {
        switch keyCode {
        case 144: .brightnessUp
        case 145: .brightnessDown
        default: nil
        }
    }

    /// The level after one press, on the system's grid of 16 steps, or 64
    /// with Shift-Option (fine steps). A level between steps snaps to the
    /// nearest one first.
    static func step(_ level: Float, up: Bool, fine: Bool) -> Float {
        let steps: Float = fine ? 64 : 16
        let current = (level * steps).rounded()
        let next = up ? current + 1 : current - 1
        return min(max(next / steps, 0), 1)
    }
}
