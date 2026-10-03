# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`thenotch` is a macOS menu-bar-style app that renders a "Dynamic Island" around the MacBook notch (similar to DynamicLake). The project is at an early scaffolding stage: most files under `thenotch/Core/` are empty placeholders defining the intended architecture.

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

Run the app from Xcode (⌘R). Because of `LSUIElement`, it has no Dock icon or main window — quit it via Activity Monitor / `killall thenotch` until a quit control exists.

## Architecture

- **Entry point** (`thenotch/App/`): `thenotchApp` declares only a `Settings` scene and hands control to `AppDelegate` via `@NSApplicationDelegateAdaptor`. All on-screen UI is driven from AppKit, not SwiftUI scenes — do not add a `WindowGroup`.
- **Intended flow** (`thenotch/Core/`):
  - `Window/IslandController` — created in `AppDelegate.applicationDidFinishLaunching`; owns the panel, positions it over the notch, reacts to screen changes.
  - `Window/IslandPanel` — borderless, non-activating `NSPanel` sitting at/above the menu bar level, hosting SwiftUI via `NSHostingView`.
  - `Geometry/NotchGeometry` — computes the notch rect from `NSScreen` (`safeAreaInsets`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`); on screens without a notch it returns a simulated 190pt-wide notch under the menu bar. `targetScreen()` prefers the notched display.
  - `State/IslandState` — observable model (collapsed/expanded, content) shared between controller and views.
  - `UI/IslandView` + `UI/NotchShape` — SwiftUI rendering of the island and its notch-matching shape.
- The Xcode project uses **file-system synchronized groups**: any file added under `thenotch/` is automatically part of the target; no `project.pbxproj` edits are needed when adding/moving files.

## Build settings that matter

- **App Sandbox is OFF** and Hardened Runtime is ON — intentional, because notch apps need system-level access (media info, screen/window APIs). Distribution is outside the Mac App Store (notarization).
- **Deployment target: macOS 14.0** (target-level setting overrides the project-level 26.6). Guard newer APIs with `#available`.
- **Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, approachable concurrency OFF.** Types are *not* implicitly `@MainActor`, so mark AppKit/SwiftUI-facing types (`AppDelegate`, `IslandController`, `IslandPanel`, `IslandState`) with `@MainActor` explicitly.
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`); add keys via `INFOPLIST_KEY_*` build settings rather than a plist file.

## Git workflow

`main` is protected: never commit or push to it directly. Work on a new branch (`<type>/<topic>`, e.g. `feat/island-panel`), push it, and open a PR. A PR may only be merged once every CI check (`build-and-test`) passes. Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:` …).
