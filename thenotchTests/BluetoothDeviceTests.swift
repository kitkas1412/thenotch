//
//  BluetoothDeviceTests.swift
//  thenotchTests
//

import Testing
@testable import thenotch

struct BluetoothDeviceTests {
    typealias Battery = BluetoothDevice.Battery

    func device(_ battery: Battery) -> BluetoothDevice {
        BluetoothDevice(address: "aa-bb", name: "AirPods", symbol: "airpods", battery: battery)
    }

    @Test func zeroMeansUnknown() {
        #expect(Battery.level(0) == nil)
        #expect(Battery.level(88) == 88)
        #expect(Battery.level(101) == nil)
    }

    @Test func headlineIsTheLowerBud() {
        #expect(Battery(left: 88, right: 40, case: 90).headline == 40)
        #expect(Battery(left: 88).headline == 88)
        #expect(Battery(single: 64).headline == 64)
        #expect(Battery(case: 30).headline == nil)
    }

    @Test func detailListsEveryBattery() {
        #expect(device(Battery(left: 88, right: 89, case: 26)).detail == "Left 88% · Right 89% · Case 26%")
        #expect(device(Battery(left: 88, right: 89)).detail == "Left 88% · Right 89%")
        #expect(device(Battery(single: 64)).detail == "Battery 64%")
        #expect(device(Battery()).detail == "Connected")
    }

    @Test func appleHeadphonesBySymbol() {
        #expect(BluetoothDevice.symbol(vendorID: 76, productID: 0x2027, majorClass: 4, minorClass: 6, hasBuds: true) == "airpodspro")
        #expect(BluetoothDevice.symbol(vendorID: 76, productID: 0x201F, majorClass: 4, minorClass: 6, hasBuds: false) == "airpodsmax")
        #expect(BluetoothDevice.symbol(vendorID: 76, productID: 0x2019, majorClass: 4, minorClass: 6, hasBuds: true) == "airpods")
    }

    @Test func otherDevicesByClass() {
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 4, minorClass: 6, hasBuds: false) == "headphones")
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 4, minorClass: 5, hasBuds: false) == "hifispeaker.fill")
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 5, minorClass: 0x10, hasBuds: false) == "keyboard.fill")
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 5, minorClass: 0x20, hasBuds: false) == "computermouse.fill")
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 5, minorClass: 0x02, hasBuds: false) == "gamecontroller.fill")
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 2, minorClass: 0, hasBuds: false) == "iphone")
        #expect(BluetoothDevice.symbol(vendorID: 0, productID: 0, majorClass: 0, minorClass: 0, hasBuds: false) == "wave.3.right")
    }
}

struct BluetoothAddressTests {
    @Test func readsTheAddressInAnAudioUID() {
        #expect(BluetoothDevice.address(fromAudioUID: "F8-1E-49-A0-34-A8:output") == "f8-1e-49-a0-34-a8")
        #expect(BluetoothDevice.address(fromAudioUID: "BuiltInSpeakerDevice") == nil)
        #expect(BluetoothDevice.address(fromAudioUID: "8CBD00C3-3232-4D88-A223-F39900000003") == nil)
    }

    @Test func addressesMatchAcrossSpellings() {
        #expect(BluetoothDevice.normalized("F8:1E:49:A0:34:A8") == BluetoothDevice.normalized("f8-1e-49-a0-34-a8"))
    }
}
