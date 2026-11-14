import Testing
@testable import thenotch

struct SettingsPaneTests {
    @Test func storedValuesParse() {
        #expect(SettingsPane(storedValue: "general") == .general)
        #expect(SettingsPane(storedValue: "tool.notch") == .tool(.notch))
    }

    @Test func legacyModulesTabMapsToNotchTool() {
        #expect(SettingsPane(storedValue: "modules") == .tool(.notch))
    }

    @Test(arguments: ["", "bogus", "tool.", "tool.bogus", "Tool.notch", "tool.notch.extra", "notch"])
    func unknownValuesFallBackToGeneral(value: String) {
        #expect(SettingsPane(storedValue: value) == .general)
    }

    @Test func storedValueRoundTrips() {
        let panes: [SettingsPane] = [.general] + ToolKind.allCases.map { .tool($0) }
        for pane in panes {
            #expect(SettingsPane(storedValue: pane.storedValue) == pane)
        }
        #expect(SettingsPane.general.storedValue == "general")
        #expect(SettingsPane.tool(.notch).storedValue == "tool.notch")
    }
}
