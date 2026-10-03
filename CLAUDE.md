# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`thenotch` is a macOS menu-bar-style app that renders a "Dynamic Island" around the MacBook notch (similar to DynamicLake). The project is at an early scaffolding stage: most files under `thenotch/Core/` are empty placeholders defining the intended architecture.

## Commands

Single target and scheme: `thenotch`. No test target or linter is configured yet.

```bash
# Build (Debug)
xcodebuild -project thenotch.xcodeproj -scheme thenotch -configuration Debug build

# Build without code signing (CI / headless check)
xcodebuild -project thenotch.xcodeproj -scheme thenotch -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Run the app from Xcode (⌘R). Because of `LSUIElement`, it has no Dock icon or main window — quit it via Activity Monitor / `killall thenotch` until a quit control exists.

## Architecture

- **Entry point** (`thenotch/App/`): `thenotchApp` declares only a `Settings` scene and hands control to `AppDelegate` via `@NSApplicationDelegateAdaptor`. All on-screen UI is driven from AppKit, not SwiftUI scenes — do not add a `WindowGroup`.
- **Intended flow** (`thenotch/Core/`):
  - `Window/IslandController` — created in `AppDelegate.applicationDidFinishLaunching`; owns the panel, positions it over the notch, reacts to screen changes.
  - `Window/IslandPanel` — borderless, non-activating `NSPanel` sitting at/above the menu bar level, hosting SwiftUI via `NSHostingView`.
  - `Geometry/NotchGeometry` — computes notch rect from `NSScreen` (`safeAreaInsets`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`), with a fallback for screens without a notch.
  - `State/IslandState` — observable model (collapsed/expanded, content) shared between controller and views.
  - `UI/IslandView` + `UI/NotchShape` — SwiftUI rendering of the island and its notch-matching shape.
- The Xcode project uses **file-system synchronized groups**: any file added under `thenotch/` is automatically part of the target; no `project.pbxproj` edits are needed when adding/moving files.

## Build settings that matter

- **App Sandbox is OFF** and Hardened Runtime is ON — intentional, because notch apps need system-level access (media info, screen/window APIs). Distribution is outside the Mac App Store (notarization).
- **Deployment target: macOS 14.0** (target-level setting overrides the project-level 26.6). Guard newer APIs with `#available`.
- **Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, approachable concurrency OFF.** Types are *not* implicitly `@MainActor`, so mark AppKit/SwiftUI-facing types (`AppDelegate`, `IslandController`, `IslandPanel`, `IslandState`) with `@MainActor` explicitly.
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`); add keys via `INFOPLIST_KEY_*` build settings rather than a plist file.
