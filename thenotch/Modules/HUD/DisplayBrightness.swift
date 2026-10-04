//
//  DisplayBrightness.swift
//  thenotch
//

import CoreGraphics
import Foundation

/// Brightness of the built-in display, through the private DisplayServices
/// framework (what the brightness keys use; there is no public API). It's
/// loaded at run time: if it's missing or changes, `isAvailable` is false
/// and the keys are left to macOS.
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: GetBrightness, set: SetBrightness)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return (unsafeBitCast(get, to: GetBrightness.self), unsafeBitCast(set, to: SetBrightness.self))
    }()

    /// The built-in display, if it's on (not with the lid closed).
    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    /// 0…1.
    static func brightness(of display: CGDirectDisplayID) -> Float? {
        guard let functions else { return nil }
        var value: Float = 0
        return functions.get(display, &value) == 0 ? value : nil
    }

    static func setBrightness(_ brightness: Float, of display: CGDirectDisplayID) -> Bool {
        guard let functions else { return false }
        return functions.set(display, min(max(brightness, 0), 1)) == 0
    }
}
