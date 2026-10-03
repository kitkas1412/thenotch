# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`thenotch` is a macOS menu-bar-style app that renders a "Dynamic Island" around the MacBook notch (similar to DynamicLake). The project is early in development: a black island sits over the notch and expands on hover with placeholder content; modules (Now Playing, Battery…) are not implemented yet.

## Commands

Shared scheme `thenotch` builds the app and runs the `thenotchTests` target (Swift Testing, hosted in the app). No linter is configured.

```bash
# Build (Debug)
xcodebuild -project thenotch.xcodeproj -scheme thenotch -configuration Debug build

# Run all tests (same command CI uses)
xcodebuild test -project thenotch.xcodeproj -scheme thenotch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Run a single test / suite
xcodebuild test ... -only-testing:thenotchTests/NotchGeometryTests/notchedScreenUsesAuxiliaryAreas
```

CI (`.github/workflows/ci.yml`) runs the test command on every push to `main` and every PR, on the `xcode-27` runner image. Test logs are noisy with `com.apple.linkd.autoShortcut` connection errors; they are harmless.

Keep testable logic as pure functions taking plain values (see `NotchGeometry.notchRect(frame:visibleFrame:topInset:leftArea:rightArea:)`), with a thin `NSScreen` wrapper — `NSScreen` can't be constructed in tests.

Run the app from Xcode (⌘R). Because of `LSUIElement`, it has no Dock icon or main window — quit it from its menu bar icon (capsule) → Quit, or `killall thenotch`.

## Architecture

- **Entry point** (`thenotch/App/`): `thenotchApp` declares a `MenuBarExtra` (Settings…, Quit) and a `Settings` scene, and hands control to `AppDelegate` via `@NSApplicationDelegateAdaptor`. `AppDelegate` owns `AppSettings` and the `IslandController`. The island itself is driven from AppKit, not SwiftUI scenes — do not add a `WindowGroup`.
- **Intended flow** (`thenotch/Core/`):
  - `Window/IslandController` — created in `AppDelegate.applicationDidFinishLaunching`; owns the panel, positions it over the notch, reacts to screen changes.
  - `Window/IslandPanel` — borderless, non-activating `NSPanel` sitting at/above the menu bar level, hosting SwiftUI via `NSHostingView`.
  - `Geometry/NotchGeometry` — computes the notch rect from `NSScreen` (`safeAreaInsets`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`); on screens without a notch it returns a simulated 190pt-wide notch under the menu bar. `targetScreen()` prefers the notched display.
  - `State/IslandState` — observable model (collapsed/expanded, content) shared between controller and views.
  - `State/HoverPolicy` — pure open/close decision from the pointer position, with hysteresis (exit region larger than entry). The controller feeds it from a global `mouseMoved` monitor plus an `.activeAlways` tracking area on the hosting view (AppKit only sends `mouseMoved` to the key window, and the panel never becomes key) and debounces opening by 150 ms; the panel only accepts mouse events while expanded.
  - `Modules/IslandModule` + `State/ActivityCenter` — features are `IslandModule`s. To add one, add a case to `ModuleKind` (`thenotch/Settings/AppSettings.swift`); its `rawValue` must equal the module's `id`. `IslandController.applyModuleSettings()` starts/stops modules as they're toggled in Settings. A module publishes a `LiveActivity` (priority, optional expiry) to `state.activities`; `ActivityCenter` picks the one shown in compact mode, and `IslandView` renders that module's `compactLeading`/`compactTrailing` wings beside the notch and its `expandedView` when open.
  - `UI/IslandView` + `UI/NotchShape` — SwiftUI rendering of the island and its notch-matching shape.
- **Feature modules** live in `thenotch/Modules/<Name>/` (service + module + views). `NowPlaying` combines `NowPlayingService` (state from Spotify/Music notifications, AppleScript controls, artwork cache) with compact wings (artwork, level meter) and an expanded player.
- The Xcode project uses **file-system synchronized groups**: any file added under `thenotch/` is automatically part of the target; no `project.pbxproj` edits are needed when adding/moving files.

## Build settings that matter

- **App Sandbox is OFF** and Hardened Runtime is ON — intentional, because notch apps need system-level access (media info, screen/window APIs). Distribution is outside the Mac App Store (notarization).
- **Deployment target: macOS 14.0** (target-level setting overrides the project-level 26.6). Guard newer APIs with `#available`.
- **Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, approachable concurrency OFF.** Types are *not* implicitly `@MainActor`, so mark AppKit/SwiftUI-facing types (`AppDelegate`, `IslandController`, `IslandPanel`, `IslandState`) with `@MainActor` explicitly.
- **Automation (Apple Events)** is enabled via `AUTOMATION_APPLE_EVENTS = YES` (hardened-runtime entitlement) and `INFOPLIST_KEY_NSAppleEventsUsageDescription`. Now Playing reads state from Spotify/Music distributed notifications (no permission) and uses AppleScript only for controls/position; never script an app that isn't running (`tell application` would launch it). Permission sticks only with a stable signing identity (your Apple Development team), not ad-hoc signing.
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`); add keys via `INFOPLIST_KEY_*` build settings rather than a plist file.

## Git workflow

`main` is protected: never commit or push to it directly. Work on a new branch (`<type>/<topic>`, e.g. `feat/island-panel`), push it, and open a PR. A PR may only be merged once every CI check (`build-and-test`) passes. Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:` …).

The `/ship` skill (`.claude/skills/ship/`) automates branch → test → commit → push; it does not open the PR — the maintainer does that on GitHub. A `PreToolUse` hook (`.claude/hooks/block-main-commits.sh`) blocks `git commit`/`git push` on `main`; `gh pr create` and `gh pr merge` are denied in `.claude/settings.json` — merging is the maintainer's call.
