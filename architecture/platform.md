# Platform services, releases and updates

Detailed reference split out of [CLAUDE.md](../CLAUDE.md): the shared services in `thenotch/Platform/`, the release build and Sparkle updates.

## Platform services (`thenotch/Platform/`), shared by tools

- `Permissions/PermissionCenter` — `Permission` (Accessibility, Screen Recording, Input Monitoring, Automation, Bluetooth) with `status(_:)` (never prompts; Automation is `.unknown`, it is per target app), `request(_:)` (may prompt; Automation opens its pane) and `openSettings(_:)`. The Accessibility modules, Window Management and the Bluetooth module still use `AccessibilityPermission` and `BluetoothPermission`.
- `Input/Shortcut` + `Input/HotKeyCenter` — global shortcuts through Carbon `RegisterEventHotKey` (no permission).
  - `Shortcut` is a pure value (Carbon key code and modifiers, `displayString` in ⌃⌥⇧⌘ order); `validation` needs ⌘ or ⌃ unless it is an F-key, and refuses reserved macOS combos (Spotlight, App switcher, Screenshot…).
  - `HotKeyCenter` registers handlers under a string id with one lazily installed event handler (removed when no entry is left); `RegistrationResult` is `registered`, `unavailable` (another app has it) or `invalid`; `suspend()` releases every hotkey while a `ShortcutRecorder` captures keys and `resume()` brings them back, retrying the unavailable ones; `conflictingID(for:excluding:)` finds another of our actions on the same shortcut.
  - `ShortcutAction` (id, title, owning `ToolKind`, `defaultShortcut`) lists the actions in `ShortcutAction.all`; `actions(for:)` gives one tool's. They are `notch.toggle` (unbound by default), `windows.<WindowAction>` (the 17 Window Management actions) and `clipboard.showHistory` (⌃⌘V by default).
  - `AppSettings` keeps the effective shortcut per action (`shortcut(for:)`, `nil` when unbound): the default until the user records one (stored as JSON under `shortcut.<actionID>`, `setShortcut`), or none once cleared (stored as JSON `null`, so the default doesn't come back). `resetShortcut(for:)` removes the stored value and goes back to the default.
  - `observeShortcuts(_:)` returns a `ShortcutObservation` token that calls back with the action id after a shortcut really changed; it is held weakly, so keep the token while observing, and `cancel()` (or releasing it) stops the calls.
  - `NotchTool` registers `notch.toggle` while it runs and calls `IslandController.toggleFromShortcut()` (opens like a click, or closes; ignored while not started, hidden, dragging or a menu is tracked).
- `Accessibility/AXWindow` — the focused window of the frontmost app, read and moved through the Accessibility API (needs `AccessibilityPermission`; our own app is skipped). Frames are in AX coordinates; every call is bounded by a 0.25 s messaging timeout. `setFrame` sets size, position, then size again (the first size can be clamped by the display the window is on); a window that can't be moved returns `false`, and one that can't be resized is only moved.

## Releases

`scripts/build-release.sh [version]` builds a universal, ad-hoc-signed, stripped Release (`DEPLOYMENT_POSTPROCESSING`/`STRIP_INSTALLED_PRODUCT` in the Release configuration, since the script runs `xcodebuild build`, not `archive`; the dSYMs stay in the build folder) (entitlements from `scripts/release.entitlements`, no `get-task-allow`) into `dist/` as DMG + zip. Pushing a `v*` tag runs `.github/workflows/release.yml`, which publishes a GitHub Release using the matching `CHANGELOG.md` section; the tag must match `MARKETING_VERSION`.

## Updates (`App/Updater`)

- Sparkle 2 via SPM; `SPUStandardUpdaterController` is not started under unit tests.
- `SUFeedURL`, `SUPublicEDKey` and the daily automatic check (`SUEnableAutomaticChecks`, `SUScheduledCheckInterval` = 86400) live in `Config/Info.plist` (merged into the generated Info.plist; kept outside `thenotch/` so the synchronized group doesn't copy it).
- The Release workflow signs the zip with the `SPARKLE_PRIVATE_KEY` secret and attaches `appcast.xml` (`scripts/make-appcast.sh`); each release needs a higher `CURRENT_PROJECT_VERSION`.
- Ad-hoc releases need `com.apple.security.cs.disable-library-validation` (`scripts/release.entitlements`): without a Team ID, the hardened runtime refuses to load the embedded Sparkle.framework and the app won't launch; drop it once releases use a Developer ID. Debug builds are team-signed and don't need it.
