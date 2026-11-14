import CoreBluetooth
import IOKit.hid
import Testing
@testable import thenotch

struct PermissionCenterTests {
    @Test(arguments: [
        (Permission.accessibility, "Privacy_Accessibility"),
        (.screenRecording, "Privacy_ScreenCapture"),
        (.inputMonitoring, "Privacy_ListenEvent"),
        (.automation, "Privacy_Automation"),
        (.bluetooth, "Privacy_Bluetooth"),
    ])
    func settingsURLUsesPrivacyAnchor(permission: Permission, anchor: String) {
        #expect(permission.systemSettingsURL?.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    @Test func everyPermissionHasTitleAndURL() {
        for p in Permission.allCases {
            #expect(!p.title.isEmpty)
            #expect(p.systemSettingsURL != nil)
        }
        #expect(Set(Permission.allCases.map(\.title)).count == Permission.allCases.count)
    }

    @Test func hidAccessMapping() {
        #expect(PermissionCenter.status(hidAccess: kIOHIDAccessTypeGranted) == .granted)
        #expect(PermissionCenter.status(hidAccess: kIOHIDAccessTypeDenied) == .denied)
        #expect(PermissionCenter.status(hidAccess: kIOHIDAccessTypeUnknown) == .notDetermined)
        #expect(PermissionCenter.status(hidAccess: IOHIDAccessType(rawValue: 99)) == .unknown)
    }

    @Test func bluetoothMapping() {
        #expect(PermissionCenter.status(bluetooth: .allowedAlways) == .granted)
        #expect(PermissionCenter.status(bluetooth: .denied) == .denied)
        #expect(PermissionCenter.status(bluetooth: .restricted) == .denied)
        #expect(PermissionCenter.status(bluetooth: .notDetermined) == .notDetermined)
    }

    @Test func automationStatusIsUnknownWithoutTarget() {
        #expect(PermissionCenter.status(.automation) == .unknown)
    }
}
