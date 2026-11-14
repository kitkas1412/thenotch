# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`thenotch` is a macOS menu-bar-style app that renders a "Dynamic Island" around the MacBook notch (similar to DynamicLake). A black island sits over the notch and expands on hover; features are modules (Now Playing, Battery, Shelf, Volume & Brightness, Bluetooth, Notifications, AI Agents (Claude Code, Codex)). Releases are published on GitHub (see `CHANGELOG.md`).

## Commands

Shared scheme `thenotch` builds the app and runs the `thenotchTests` target (Swift Testing, hosted in the app). No linter or formatter is configured (swift-format may be installed locally, but the repo has no config — don't run it on the codebase).

Baseline as of 2026-11-14: the Debug build takes ~8 s and has 5 compiler warnings, all in older code (`IslandEnvironment.swift` `@Entry` closure, `IslandController.swift` `NSEvent` Sendable, `SystemVolume.swift` `UnsafeRawPointer`, `NotificationBannerWatcher.swift` main-actor static, `NowPlayingService.swift` `NSImageRep`/`Task` Sendable) plus an `appintentsmetadataprocessor` tooling note; a new warning is a regression. The tests (479 Swift Testing tests in 60 suites) pass in ~10 s, and XCTest's "Executed 0 tests" line is expected. When piping `xcodebuild` output through `grep`/`tail`, use `set -o pipefail` so a failing run isn't masked.

```bash
# Build (Debug)
xcodebuild -project thenotch.xcodeproj -scheme thenotch -configuration Debug build

# Run all tests (same command CI uses)
xcodebuild test -project thenotch.xcodeproj -scheme thenotch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Run a single test / suite
xcodebuild test ... -only-testing:thenotchTests/NotchGeometryTests/notchedScreenUsesAuxiliaryAreas
```

Releases: `scripts/build-release.sh [version]` builds a universal, ad-hoc-signed Release into `dist/` (DMG + zip); pushing a `v*` tag publishes a GitHub Release (the tag must match `MARKETING_VERSION`). Details: [architecture/platform.md](architecture/platform.md).

CI (`.github/workflows/ci.yml`) runs the test command on every push to `main` and every PR, on the `xcode-27` runner image. Test logs are noisy with `com.apple.linkd.autoShortcut` connection errors; they are harmless.

Keep testable logic as pure functions taking plain values (see `NotchGeometry.notchRect(frame:visibleFrame:topInset:leftArea:rightArea:)`), with a thin `NSScreen` wrapper — `NSScreen` can't be constructed in tests.

Run the app from Xcode (⌘R). Because of `LSUIElement`, it has no Dock icon or main window — quit it from its menu bar icon (capsule) → Quit, or `killall thenotch`. Run one copy at a time (a copy started with `open` and one from Xcode both tap keys, watch Notification Center and listen on the Claude Code socket). With Volume & Brightness on, a copy paused in the debugger (a breakpoint, a crash) holds up every key press and pointer event for about a second, system-wide: its key tap can't answer. Stop or quit it.

## Architecture overview

The detailed per-area text lives in `architecture/`, read on demand (not imported).

- **Entry point** (`thenotch/App/`): `thenotchApp` declares a `MenuBarExtra` (`.window` style, hosting `App/MenuPanel`: the System Monitor section while that tool is on, then Settings…, Check for Updates…, Quit rows; the rows that open a window or app close the panel first) and a `Settings` scene, and hands control to `AppDelegate` via `@NSApplicationDelegateAdaptor`. `AppDelegate` owns `AppSettings`, `Updater`, the `HotKeyCenter`, the `SystemSampler` (`systemMonitor`) and the `ToolHost`, and starts the host in `applicationDidFinishLaunching`. `App/AppIdentity` holds the name and bundle-derived strings (name, `bundleID`, queue label prefix and `queueLabel(_:)`, log subsystem, `supportDirectory`, `hookSourcePrefix`, hooks `backupExtension`): use it instead of literals, so a rename edits one file. The island itself is driven from AppKit, not SwiftUI scenes — do not add a `WindowGroup`.
- **Tools** (`thenotch/Tools/`, `App/ToolHost`): the app is a suite of tools. A `Tool` (`@MainActor` protocol: `id`, `start()`, `stop()`) is built from a `ToolKind` (`makeTool(context:)` with a `ToolContext { settings, hotKeys, systemMonitor, islandContributions }`; `rawValue` must equal the tool's `id`). `ToolKind` has `.notch` (on by default), `.systemMonitor`, `.windowManagement` and `.clipboard` (off). To add a tool, add a case to `ToolKind` (title, symbol, summary, `makeTool`), a pane in `Settings/Panes/` and a case in `SettingsView`'s detail switch. `ToolHost` builds every tool at init, starts the enabled ones in `ToolKind` order and stops them in reverse; the switch `tool.<id>.enabled` (`AppSettings.setToolEnabled`, `onToolsChange`) starts or stops a tool while the host runs. Tools are never started under a host that was not started.
- **Settings** (`thenotch/Settings/`): `SettingsView` is a `NavigationSplitView` in the `Settings` scene: a sidebar with General and, under Tools, one entry per `ToolKind` (icon tile from `SettingsIconTile`). The selected pane is stored in `@AppStorage("settings.pane")` as `SettingsPane.storedValue`: `general` or `tool.<id>` (the legacy `modules` opens Notch; anything unknown, General). Panes live in `Settings/Panes/` (`GeneralPane`, `NotchPane`, `SystemMonitorPane`, `WindowManagementPane`, `ClipboardPane`), shared views in `Settings/Components/` (`SettingsToggleRow`, `SettingsNote`, `SettingsNotice` with a symbol and the action that fixes it, `ShortcutRecorder`/`ShortcutRow`): grouped forms with small controls, each tool or module a section with its icon tile and a regular switch, its options shown under it only while it's on. `NotchPane` shows the Notch switch, the shortcuts, then the modules; while Notch is off the module sections are hidden (a module can only be turned off while the island runs, which removes its hooks).
- **Platform services** (`thenotch/Platform/`): `PermissionCenter` (status/request/open Settings per permission), `Shortcut` + `HotKeyCenter` + `ShortcutAction` (global shortcuts via Carbon, stored per action in `AppSettings`), `AXWindow` (focused window through the Accessibility API); also Sparkle updates (`App/Updater`) and release builds. Details: [architecture/platform.md](architecture/platform.md).
- **Island and Notch tool** (`thenotch/Tools/Notch/NotchTool`, `thenotch/Core/`): `NotchTool` owns the `IslandController`, which drives the borderless `IslandPanel` over the notch; hover grows the island, a click opens it (`HoverPolicy`), state is in `IslandState`, drawing in `IslandView`. Details: [architecture/island.md](architecture/island.md).
- **Island modules** (`thenotch/Modules/<Name>/`, service + module + views): features are `IslandModule`s publishing `LiveActivity`s through `ActivityCenter`. To add one, add a case to `ModuleKind` (`thenotch/Settings/AppSettings.swift`); its `rawValue` must equal the module's `id`. Built in: Now Playing, Battery, Shelf, Volume & Brightness (`Modules/HUD`), Bluetooth, Notifications, AI Agents (`Modules/ClaudeCode`). Contributed modules (a tool adds one through `IslandContributions`) and file drops are in the island reference. Details: [architecture/modules.md](architecture/modules.md) and [architecture/island.md](architecture/island.md).
- **Design system**: the island is always black (forced dark color scheme), so views use semantic styles (`.primary`, `.secondary`) and the tokens in `DESIGN.md` / `Core/UI/DesignSystem/` (shared views in `Core/UI/Components/`), not literal sizes, opacities or colors. Menu panel UI (System Monitor) uses system fonts, colors and controls instead.
- **Other tools** (System Monitor, Clipboard, Window Management; `thenotch/Tools/`): System Monitor samples CPU, memory, network and disk for the menu panel; Clipboard keeps an encrypted history shown in the island; Window Management moves windows with global shortcuts. Details: [architecture/tools.md](architecture/tools.md).
- The Xcode project uses **file-system synchronized groups**: any file added under `thenotch/` is automatically part of the target; no `project.pbxproj` edits are needed when adding/moving files.

## Traps

- Do not add a `WindowGroup`; the island is AppKit.
- `MediaKeyTap` sees every key press and macOS waits for it: it must never wait on the main thread.
- Never script an app that isn't running (`tell application` would launch it).
- Don't add `-N` to the hooks' `nc` command: on macOS nc it is a probe count, not shutdown-on-EOF, and it would break the hook silently.
- Never touch Codex's `config.toml`.
- Don't use Anthropic's or OpenAI's logos or the Claude Code mascot (trademark guidelines; releases are public).
- macOS 26's `com.apple.ncprefs.plist` isn't updated by System Settings any more: don't read styles or preview settings from it.
- An `onDrop` inside the clipped island never receives drops: `IslandView` has the single `onDrop`.
- Logs never contain clipboard content or notification text.
- IOBluetooth callbacks may arrive off the main thread: hop to the main queue.
- Ad-hoc releases need `com.apple.security.cs.disable-library-validation` (`scripts/release.entitlements`), or the embedded Sparkle.framework won't load.

## Before you change X, read Y

- Notch tool, island window, hover/click, `IslandModule`, file drops, Shelf, contributions, rendering: [architecture/island.md](architecture/island.md)
- Now Playing, Volume & Brightness, Bluetooth, Notifications, AI Agents (hooks): [architecture/modules.md](architecture/modules.md)
- System Monitor, Clipboard, Window Management: [architecture/tools.md](architecture/tools.md)
- Permissions, shortcuts/hotkeys, `AXWindow`, release script, Sparkle updates: [architecture/platform.md](architecture/platform.md)

## Build settings that matter

- **App Sandbox is OFF** and Hardened Runtime is ON — intentional, because notch apps need system-level access (media info, screen/window APIs). Distribution is outside the Mac App Store (notarization).
- **Deployment target: macOS 14.0** (target-level setting overrides the project-level 26.6). Guard newer APIs with `#available`.
- **Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, approachable concurrency OFF.** Types are *not* implicitly `@MainActor`, so mark AppKit/SwiftUI-facing types (`AppDelegate`, `IslandController`, `IslandPanel`, `IslandState`) with `@MainActor` explicitly.
- **Automation (Apple Events)** is enabled via `AUTOMATION_APPLE_EVENTS = YES` (hardened-runtime entitlement) and `INFOPLIST_KEY_NSAppleEventsUsageDescription`. Now Playing reads state from Spotify/Music distributed notifications (no permission) and uses AppleScript only for controls/position; never script an app that isn't running (`tell application` would launch it). Permission sticks only with a stable signing identity (your Apple Development team), not ad-hoc signing.
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`); add keys via `INFOPLIST_KEY_*` build settings rather than a plist file.

## Git workflow

`main` is protected: never commit or push to it directly. Work on a new branch (`<type>/<topic>`, e.g. `feat/island-panel`), push it, and open a PR. A PR may only be merged once every CI check (`build-and-test`) passes. Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:` …).

The `/ship` skill (`.claude/skills/ship/`) automates branch → test → commit → push and stops there. A `PreToolUse` hook (`.claude/hooks/block-main-commits.sh`, needs `jq`) blocks `git commit`/`git push` on `main`; direct `gh pr create` and `gh pr merge` are denied in `.claude/settings.json`. The repo is registered with `~/.claude/hooks/git-publish.sh` at level `merge` (Conventional Commits; CI-file changes refused): the orchestrator's `release-manager` may open a draft PR and squash merge only through that script, only when the approved plan includes it, only after every CI check (`build-and-test`) passes, and only after the maintainer confirms the merge.

- PRs opened through `git-publish.sh` must use the body headings What / Why / How tested / Risks (the script refuses others). PRs opened by hand follow `.github/pull_request_template.md` (Summary, Test plan, Notes).
- `git-publish.sh` refuses to merge PRs that touch `CLAUDE.md`, `.claude/**` or `.github/**`; the maintainer merges those by hand.
- `.agents/skills/ship/` is the Codex copy of `.claude/skills/ship/`; it is a local, gitignored copy. Keep both in sync.
- `.codex/hooks.json` (also local and gitignored) uses an absolute path (`/Users/neco/Developer/thenotch/.codex/hooks/...`), so it is not portable.
