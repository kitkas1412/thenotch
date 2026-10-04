# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`thenotch` is a macOS menu-bar-style app that renders a "Dynamic Island" around the MacBook notch (similar to DynamicLake). A black island sits over the notch and expands on hover; features are modules (Now Playing, Battery, Shelf). v0.1.0 is released on GitHub.

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

Releases: `scripts/build-release.sh [version]` builds a universal, ad-hoc-signed Release (entitlements from `scripts/release.entitlements`, no `get-task-allow`) into `dist/` as DMG + zip. Pushing a `v*` tag runs `.github/workflows/release.yml`, which publishes a GitHub Release using the matching `CHANGELOG.md` section; the tag must match `MARKETING_VERSION`.

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
  - `Modules/IslandModule` + `State/ActivityCenter` — features are `IslandModule`s. To add one, add a case to `ModuleKind` (`thenotch/Settings/AppSettings.swift`); its `rawValue` must equal the module's `id`. `IslandController.applyModuleSettings()` starts/stops modules as they're toggled in Settings. A module publishes a `LiveActivity` (priority, optional expiry) to `state.activities`; `ActivityCenter` picks the one shown in compact mode, and `IslandView` renders that module's `compactLeading`/`compactTrailing` wings beside the notch and its `expandedView` when open. A module reports `hasExpandedContent` (hovering opens the island only if some module has content; `IslandState.expandedModule` is `nil` otherwise) its `compactContentWidth` (wings are that wide plus equal padding, `IslandState.compactPadding`), When two or more modules have content, `IslandView` shows a tab per module left of the notch (`IslandState.showsTabs`, `select(_:)` re-pins until the island closes). Each module also reports its `expandedContentHeight` (content only, with its bottom margin; `IslandState.expandedSize` adds the notch height and the margin below it, and the total must stay ≤ `IslandController.panelSize.height`).
  - **File drops**: a module conforming to `FileDropReceiving` (the Shelf) takes files dropped on the island. The controller watches global `leftMouseDown/Dragged/Up` events; near the notch it checks the drag pasteboard (`FileDrag`: `changeCount` must have changed since mouse-down, since the pasteboard keeps the previous drag's contents) and opens the island pinned to that module, using the wider `HoverPolicy.dragEntryRect`. `IslandView`'s `onDrop` loads them via `FileDrop` as `DroppedFile`s: file URLs are referenced, other content (file promises, images…) is saved into `Application Support/<bundle id>/Dropped/<uuid>/` and marked `isOwned` — the Shelf deletes those folders when the item leaves, and orphans at start. The shelf persists as `Shelf.json` (bookmarks) via `ShelfPersistence`; expiry (`AppSettings.shelfLifetime`) uses one sleeping task, not polling; modules read `\.isDraggingFiles` from the environment to show their own drop zones (`IslandDropZone`s, which only report their frames: `IslandView` has the single `onDrop`, outside the clip shape, and routes files to the zone under the pointer; an `onDrop` inside the clipped island gets a misplaced AppKit view and never receives drops). Dragging out: shelf tiles start an AppKit dragging session (`ShelfDrag`, so Finder can *move* the file and we learn the operation; SwiftUI's `onDrag` only copies) and call `\.beginDragOut`; the island stays open until the mouse button is released (polled). It also stays open while one of our menus tracks (`NSMenu.didBeginTracking`).
  - `UI/IslandView` + `UI/NotchShape` — SwiftUI rendering of the island and its notch-matching shape. The island is always black: it renders under a forced dark color scheme, so views use semantic styles (`.primary`, `.secondary`) rather than `.white.opacity(…)`. The design system is documented in `DESIGN.md`: tokens in `UI/DesignSystem/` (`IslandStyle` spacing/radius/size/symbol sizes/motion, `IslandColors` with `IslandFill` levels that strengthen under Increase Contrast and `IslandSignal` status colors, `IslandTypography` `Font.island*` styles) and shared views in `UI/Components/` (`.islandIcon`/`.islandText` button styles, `IslandEmptyState`, `IslandDropZone`, `IslandProgressBar`, `.islandContentMargins()`). Views use these tokens, not literal sizes, opacities or colors.
- **Feature modules** live in `thenotch/Modules/<Name>/` (service + module + views). `NowPlaying` combines `NowPlayingService` (state from Spotify/Music notifications, AppleScript controls, artwork cache) with compact wings (artwork, level meter tinted by `ArtworkTint`) and an expanded player: a Music-only favorite star (`favorited`, falling back to `loved` on older Music; Spotify's scripting can't set it) and an audio output picker (`AudioOutputs`, CoreAudio, read when the island opens).
- **Updates** (`App/Updater`): Sparkle 2 via SPM; `SPUStandardUpdaterController` is not started under unit tests. `SUFeedURL` and `SUPublicEDKey` live in `Config/Info.plist` (merged into the generated Info.plist; kept outside `thenotch/` so the synchronized group doesn't copy it). The Release workflow signs the zip with the `SPARKLE_PRIVATE_KEY` secret and attaches `appcast.xml` (`scripts/make-appcast.sh`); each release needs a higher `CURRENT_PROJECT_VERSION`. Ad-hoc releases need `com.apple.security.cs.disable-library-validation` (`scripts/release.entitlements`): without a Team ID, the hardened runtime refuses to load the embedded Sparkle.framework and the app won't launch; drop it once releases use a Developer ID. Debug builds are team-signed and don't need it.
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
