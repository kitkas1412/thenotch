//
//  AudioOutputs.swift
//  thenotch
//

import CoreAudio
import Observation

/// An audio output device (built-in speakers, headphones, AirPlay…).
struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    /// SF Symbol for the kind of device.
    var symbol: String {
        Self.symbol(forTransport: transport)
    }

    static func symbol(forTransport transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
        default: "hifispeaker"
        }
    }
}

/// System audio outputs and the default one, read with CoreAudio when the
/// island opens (no listeners, so it costs nothing in between).
@MainActor
@Observable
final class AudioOutputs {
    private(set) var devices: [AudioOutput] = []
    private(set) var currentID: AudioDeviceID?

    var current: AudioOutput? {
        devices.first { $0.id == currentID }
    }

    func refresh() {
        devices = Self.outputDeviceIDs().compactMap { id in
            guard let name = Self.name(of: id) else { return nil }
            return AudioOutput(id: id, name: name, transport: Self.transport(of: id))
        }
        currentID = Self.defaultOutputID()
    }

    /// Makes `id` the system's default output, as Sound settings would.
    func select(_ id: AudioDeviceID) {
        var device = id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device
        )
        if status == noErr {
            currentID = id
        }
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func outputDeviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutputStreams)
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }

    private static func defaultOutputID() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown
        else { return nil }
        return id
    }
}
