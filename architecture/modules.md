# Island modules

Detailed reference split out of [CLAUDE.md](../CLAUDE.md): Now Playing, Volume & Brightness, Bluetooth, Notifications and AI Agents (modules live in `thenotch/Modules/<Name>/`: service + module + views).

## Now Playing

`NowPlaying` combines `NowPlayingService` (state from Spotify/Music notifications, AppleScript controls, artwork cache) with compact wings (artwork, level meter tinted by `ArtworkTint`) and an expanded player: a progress bar that seeks on click or drag (`set player position`, applied at once and re-read if the app refuses; the island stays open until the button is released), a Music-only favorite star (`favorited`, falling back to `loved` on older Music; Spotify's scripting can't set it) and an audio output picker (`AudioOutputs`, CoreAudio, read when the island opens).

## Volume & Brightness (`Modules/HUD`, `ModuleKind.hud`, off by default: `ModuleKind.isOnByDefault`)

`MediaKeyTap` is a Quartz event tap on its own thread (it sees every key press, and macOS waits for it, so typing must never wait on the main thread; `HUDKeys.handle` acts on the key there, CoreAudio and DisplayServices being thread-safe, and only the display hops to the main queue) (needs Accessibility, `AccessibilityPermission`, asked for when the module is turned on in Settings) that takes the volume, mute and brightness keys (`.systemDefined` events, `MediaKey.press(subtype:data1:)`, plus key codes 144/145) and returns whether they were handled — handled keys (press and release) never reach macOS, so its overlay doesn't show.

- Volume uses CoreAudio (`SystemVolume`, the default output's `VirtualMainVolume`/mute), brightness the private DisplayServices framework loaded with `dlopen` (`DisplayBrightness`, built-in display only).
- Keys it can't act on (no settable volume, no built-in display, the framework missing, Option alone) pass through.
- Steps follow macOS: 1/16, 1/64 with Shift-Option (`MediaKey.step`).
- The level shows as a `LiveActivity` (priority 60, 1.5 s) with a symbol and an `IslandProgressBar`; no expanded content.
- The tap retries when `com.apple.accessibility.api` is posted.

## Bluetooth (`Modules/Bluetooth`, `ModuleKind.bluetooth`, off by default)

`BluetoothService` reports a device on two events: an IOBluetooth connect notification (devices already connected at start are skipped; disconnects are watched per device), and the default output moving to a Bluetooth audio device (a CoreAudio listener; the UID, e.g. `F8-1E-49-A0-34-A8:output`, holds the address: `BluetoothDevice.address(fromAudioUID:)`) — AirPods often stay connected in their case, so taking them out only moves the sound.

- IOBluetooth calls back on the main thread *or* its own queue (the same connection arrives on both), so the callbacks are `nonisolated` and hop to the main queue.
- Addresses are compared `BluetoothDevice.normalized`; a second event for the device already peeking only updates it.
- The first IOBluetooth use asks for Bluetooth permission (`NSBluetoothAlwaysUsageDescription`; `BluetoothPermission` reads `CBManager.authorization` for Settings).
- Battery levels are `IOBluetoothDevice`'s non-public `batteryPercentSingle/Left/Right/Case` read only if it `responds(to:)` (0 = unknown), else the HID service's `BatteryPercent` in the I/O Registry (Magic devices); they're read again after 1 s and 3 s, since AirPods report late.
- A connection is a 4 s peek (`LiveActivity` priority 50): symbol (`BluetoothDevice.symbol`, Apple product IDs then device class) and the lower bud's level beside the notch, name and every battery in the open island.

## Notifications (`Modules/Notifications`, `ModuleKind.notifications`, off by default, needs Accessibility like the HUD: `ModuleKind.needsAccessibility`)

Replaces the macOS banners. There is no API for other apps' notifications.

- `NotificationBannerWatcher` observes Notification Center (`com.apple.notificationcenterui`) with an `AXObserver` (window created / created / layout changed, on the main run loop, 0.25 s messaging timeout; re-attached when Notification Center relaunches or access changes), copies the window into a plain `AXNode` tree and lets `NotificationBanners` (pure) decide: a window with `AXNotificationCenterBanner`s is a banner window — unless it holds Notification Center's panel (`AXNotificationListItems`) or a persistent banner (`AXNotificationCenterAlert`), which are left alone.
- It moves a banner window off screen (`AXPosition`; the `Close` action only takes effect after the banner has slid in, so it's visible for a second or two; each banner gets a new window, so nothing is restored), which keeps the notification in Notification Center.
- Only the texts the banner shows (`title`, `subtitle`, `body` identifiers) are read, so Show previews applies (the body is a placeholder); the banner's `AXDescription` has the full text even then, so only the app's name (its first part) comes from it.
- `RecentNotifications` keeps the last 3, in memory, cleared once the island has shown them; a new one is a 2 s `LiveActivity` (priority 55, the app's icon from `NotificationApps`, found by name) that `presents`: `ActivityCenter.onPresent` makes `IslandController.present(_:)` open the island pinned to it until it expires — not over an island the user opened, a drag or a menu, nor while `AmbientConditions.isVisible` is false; it ends by itself (`endPresentation()` closes the island) unless the user clicked the island meanwhile (`Presentation.isOwnedByUser`): from then on they close it.
- Clicking a row presses the banner (`AXPress`, opens the app on that notification) while it exists, else opens the app.
- Calls: a persistent alert with accept and decline actions is a call (`CallAlerts`, pure; action names are localized, `Name:Accept\nTarget:…`); its window is moved off screen while it rings and put back on stop, the alert is re-read every 0.5 s to see it end, and the call is a `LiveActivity` without expiry (priority 80) that `presents`: the presentation lasts until the activity is removed (`ActivityCenter.onRemove`), and a brief activity doesn't cut it short. The island shows the caller with Decline/Accept (`IslandSignal.callDecline`/`callAccept`), which perform the alert's actions.
- Debug builds launched with `-debug.fakeCall '<true/>'` show a fake call.
- macOS 26's `com.apple.ncprefs.plist` isn't updated by System Settings any more: don't read styles or preview settings from it.
- Logs never contain the text.

## AI Agents (`Modules/ClaudeCode`, `ModuleKind.claudeCode`, display name "AI Agents", off by default)

Shows Claude (the Claude Code CLI and the Claude desktop app's Code tab) and Codex (the Codex CLI and Codex in the ChatGPT app).

- **Hooks**: turning it on adds user-level hooks to `~/.claude/settings.json` (`ClaudeHooksConfig`) and, only if `~/.codex` exists, to `~/.codex/hooks.json` (`CodexHooksConfig`; `config.toml` is never touched). Codex asks the user to trust new hooks once (`/hooks` in the CLI, Settings › Hooks in the ChatGPT app), and a Codex installed later is picked up by turning the module off and on.
- Both share `AgentHooksFile`: one `matcher: ""` command per event in `events`, `{ printf 'thenotch-source: <claude|codex>\n'; cat; } | /usr/bin/nc -U -w 1 '<socket>' … || true`, so the agent never fails on a closed thenotch; `AgentSource.split` reads the first line (a payload without it, from an older install, is Claude's).
- Merged into the existing JSON; valid JSON of an unexpected shape (`unexpectedShape`) or invalid JSON is left alone; written atomically through symlinks keeping the file's POSIX permissions, the original copied once to `<file>.thenotch-backup`; hooks are found again by the socket path (an older command is replaced) and removed when the module is turned off.
- Claude's hooks are async (`ClaudeHooksConfig.usesAsync`); Codex's are synchronous (`CodexHooksConfig.usesAsync = false`) because Codex releases before rust-v0.148.0 silently skip async command hooks (github.com/openai/codex/releases/tag/rust-v0.148.0, learn.chatgpt.com/docs/hooks). A sync hook is cheap: macOS `nc -U -w 1` half-closes on stdin EOF, so it returns in about 30 ms (measured). Don't add `-N` to the command: on macOS nc it is a probe count, not shutdown-on-EOF, and it would break the hook silently.
- **Server and sessions**: `ClaudeHookServer` listens on `Application Support/<bundle id>/claude-hooks.sock` (0600), reads each connection off the main thread and hands a `ClaudeHookEvent` to the main queue — only the event name, source, session, cwd, tool name and notification type/message are kept, never prompts, replies, tool input or `AskUserQuestion`'s questions.
- `ClaudeSessions` (pure; keyed by source and session ID, so IDs can't collide) turns events into per-session states (working, needs permission, asking, waiting for input, idle; Codex's `PermissionRequest` is needs permission; stale ones pruned; `.working` and `.needsPermission` settle to idle after `workingTimeout`, 30 min, since a denial isn't reported). An asking session's row says "Has a question — answer in <Source>" (hooks can't answer). `turnStartedAt` is set by `UserPromptSubmit` (a new prompt restarts it) and cleared on Stop.
- **Activities**: a lasting one while a session works (priority 8, under Now Playing) or waits for permission or an answer (70), and a 4 s peek (`<id>.peek`, 50) when a reply finishes or a session asks for input; the open island lists the sessions, each with its source name and, while working, its turn time.
- The left wing shows the `sparkle` symbol, pulsing while a session works; the right wing shows the longest working session's turn time (`AgentElapsed.format`, `m:ss`, `h:mm:ss` from an hour; the wing width is `IslandStyle.Size.compactElapsed` while any session works, even during a peek), ticking every second only while `allowsAmbientAnimation`.
- Source names are plain text only. (Don't use Anthropic's or OpenAI's logos or the Claude Code mascot: their trademark guidelines need prior approval, and releases are public.)
