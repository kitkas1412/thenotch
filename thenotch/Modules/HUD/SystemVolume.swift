//
//  SystemVolume.swift
//  thenotch
//

import AudioToolbox
import CoreAudio

/// Volume and mute of the default output device, through CoreAudio. Some
/// devices (many HDMI displays) have neither; their keys are left to macOS.
enum SystemVolume {
    static func defaultOutput() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    /// 0…1, for all channels together.
    static func volume(of device: AudioDeviceID) -> Float? {
        read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: device, as: Float32.self)
    }

    static func setVolume(_ volume: Float, of device: AudioDeviceID) -> Bool {
        write(Float32(min(max(volume, 0), 1)), to: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: device)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool? {
        read(kAudioDevicePropertyMute, of: device, as: UInt32.self).map { $0 != 0 }
    }

    static func setMuted(_ muted: Bool, of device: AudioDeviceID) -> Bool {
        write(UInt32(muted ? 1 : 0), to: kAudioDevicePropertyMute, of: device)
    }

    static func canSetVolume(of device: AudioDeviceID) -> Bool {
        isSettable(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: device)
    }

    static func canMute(_ device: AudioDeviceID) -> Bool {
        isSettable(kAudioDevicePropertyMute, of: device)
    }

    // MARK: - Private

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> Bool {
        var address = address(selector, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID, as type: T.Type) -> T? {
        var address = address(selector, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func write<T>(_ value: T, to selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> Bool {
        var address = address(selector, scope: kAudioDevicePropertyScopeOutput)
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}
