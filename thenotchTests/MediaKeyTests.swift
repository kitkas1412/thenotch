//
//  MediaKeyTests.swift
//  thenotchTests
//

import Testing
@testable import thenotch

struct MediaKeyTests {
    /// `data1` of a special key event: the key type, then its state.
    func data1(keyType: Int, down: Bool, repeat isRepeat: Bool = false) -> Int {
        (keyType << 16) | ((down ? 0xA : 0xB) << 8) | (isRepeat ? 1 : 0)
    }

    @Test(arguments: [
        (0, MediaKey.volumeUp), (1, .volumeDown), (2, .brightnessUp), (3, .brightnessDown), (7, .mute),
    ])
    func readsSpecialKeys(keyType: Int, key: MediaKey) {
        #expect(MediaKey.press(subtype: 8, data1: data1(keyType: keyType, down: true))
            == MediaKey.Press(key: key, isDown: true, isRepeat: false))
    }

    @Test func readsReleaseAndRepeat() {
        #expect(MediaKey.press(subtype: 8, data1: data1(keyType: 0, down: false))?.isDown == false)
        #expect(MediaKey.press(subtype: 8, data1: data1(keyType: 0, down: true, repeat: true))?.isRepeat == true)
    }

    @Test func ignoresOtherKeysAndEvents() {
        #expect(MediaKey.press(subtype: 8, data1: data1(keyType: 16, down: true)) == nil)  // play
        #expect(MediaKey.press(subtype: 7, data1: data1(keyType: 0, down: true)) == nil)
        #expect(MediaKey.press(subtype: 8, data1: 0) == nil)
    }

    @Test func readsBrightnessKeyCodes() {
        #expect(MediaKey.brightnessKey(keyCode: 144) == .brightnessUp)
        #expect(MediaKey.brightnessKey(keyCode: 145) == .brightnessDown)
        #expect(MediaKey.brightnessKey(keyCode: 0) == nil)
    }

    @Test func stepsOnTheSystemGrid() {
        #expect(MediaKey.step(0.5, up: true, fine: false) == Float(9) / 16)
        #expect(MediaKey.step(0.5, up: false, fine: false) == Float(7) / 16)
        #expect(MediaKey.step(0.5, up: true, fine: true) == Float(33) / 64)
        // Between steps: snaps to the nearest, then steps.
        #expect(MediaKey.step(0.52, up: true, fine: false) == Float(9) / 16)
    }

    @Test func stepsStayInRange() {
        #expect(MediaKey.step(1, up: true, fine: false) == 1)
        #expect(MediaKey.step(0, up: false, fine: false) == 0)
    }
}
