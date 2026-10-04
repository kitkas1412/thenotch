# thenotch

A free, open-source macOS app that turns the MacBook notch into an interactive "Dynamic Island", inspired by [DynamicLake](https://dynamiclake.com).

> **Status:** early releases. Expect rough edges; [bug reports](https://github.com/kitkas1412/thenotch/issues) are welcome.

## Features

- **Island over the notch** — expands when you rest the pointer on it and closes when you move away. It never blocks the menu bar while closed.
- **Now Playing** — artwork and a level meter beside the notch while Spotify or Apple Music plays; title, artist, progress and playback controls when expanded.
- **Battery** — a short peek when you plug in or unplug the charger, or the battery drops to 20% / 10%.
- **Volume & Brightness** (off until you turn it on) — the volume and brightness keys show a small level bar beside the notch instead of the macOS overlay.
- **Bluetooth** (off until you turn it on) — AirPods and other Bluetooth devices peek beside the notch when they connect or the sound switches to them, with their battery (each AirPod and the case when you open the island).
- **Notifications** (off until you turn it on) — notifications show at the notch instead of the macOS banners: the island opens for a few seconds with the app, title and text (move the pointer onto it to keep it open). Click one to open it. An incoming FaceTime or iPhone call opens the island while it rings, to accept or decline it. Notifications still go to Notification Center; other persistent banners stay as they are.
- **Claude Code** (off until you turn it on) — a sparkle beside the notch while Claude Code works, an orange hand while it waits for your permission, a check mark when a reply is done; open the island for every session and what it's doing.
- **Settings** — turn modules on or off, launch at login.
- Works on Macs without a notch too: a simulated notch appears centered under the menu bar.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel Mac; a notched MacBook gives the best result

## Installing

1. Download `thenotch-<version>.dmg` from the [latest release](https://github.com/kitkas1412/thenotch/releases/latest).
2. Open it and drag **thenotch** into **Applications**.
3. Open thenotch. Because it isn't notarized by Apple (that needs a paid developer account), macOS blocks it the first time:
   - Click **Done** on the warning.
   - Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to the thenotch message. Confirm with your password.

   Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/thenotch.app`

thenotch lives in the menu bar (capsule icon) and has no Dock icon. Use that menu for **Settings…**, **Check for Updates…** and **Quit thenotch**.

### Updating

From 0.3.0 on, thenotch updates itself with [Sparkle](https://sparkle-project.org): menu bar icon › **Check for Updates…**, or let it check once a day, which it does from the first launch (turn it off in Settings › Updates). Updates come from this repository's releases and are installed only if they're signed with the project's key. Versions before 0.3.0 need one manual update: download the new DMG and drag thenotch into Applications, replacing the old copy. Your shelf and settings are kept.

To verify a download, compare it with `SHA256SUMS.txt` from the release: `shasum -a 256 thenotch-<version>.dmg`.

### Permissions

- **Automation (Spotify / Music)** — requested the first time you use a playback control. If you decline, the track is still shown but the controls are replaced by a link to System Settings › Privacy & Security › Automation.
- **Accessibility** — only for Volume & Brightness and Notifications, requested when you turn one on in Settings. It lets thenotch take the volume and brightness keys before macOS does, and read Notification Center's banners and move them out of sight. Without it, the keys and banners work as usual. thenotch reads only what a banner shows (with Show previews off, not the text), keeps the last few notifications in memory until you've seen them, and never saves or sends them. Brightness is set through a private macOS framework (there is no public one); if a macOS update changes it, the brightness keys go back to macOS.
- **Bluetooth** — only for the Bluetooth module, requested when you turn it on. It lets thenotch see devices connect and read their battery; nothing is sent anywhere. AirPods' battery levels come from macOS's Bluetooth framework through properties that aren't public API; if a macOS update removes them, devices still show, without a level.
- **Claude Code hooks** — not a macOS permission: turning the Claude Code module on adds hooks to `~/.claude/settings.json` (the original is kept as `settings.json.thenotch-backup`), and turning it off removes them. Each hook sends the event to thenotch over a socket on your Mac; thenotch keeps the project folder, the tool name, the notification and the questions Claude asks you (to show them in the island), never your prompts, Claude's replies or commands, and sends nothing anywhere.
- Nothing else. thenotch doesn't need Screen Recording or Full Disk Access.

Because releases are not signed with a Developer ID, macOS may ask for the Automation permission again after you update. Accessibility is the same, but macOS doesn't ask: thenotch still shows as allowed while the overlay comes back. Remove thenotch from System Settings › Privacy & Security › Accessibility (−) and turn Volume & Brightness off and on again.

## Privacy

thenotch runs entirely on your Mac and collects no data. It makes two kinds of network requests: downloading album artwork from Spotify's image server for the track that is playing, and checking this repository's latest GitHub release for an update (once a day if automatic checks are on, or when you choose Check for Updates…). The update check is a plain HTTPS request whose User-Agent names the app and its version; Sparkle's system profiling is off.

## Building from source

1. Install Xcode 27 or later, clone the repository and open `thenotch.xcodeproj`.
2. In **Signing & Capabilities**, select your own development team (a free Apple ID works).
3. Run the `thenotch` scheme (⌘R).

From the command line:

```bash
# Debug build
xcodebuild -project thenotch.xcodeproj -scheme thenotch -configuration Debug build

# Tests
xcodebuild test -project thenotch.xcodeproj -scheme thenotch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Release DMG + zip in dist/ (universal, ad-hoc signed)
scripts/build-release.sh
```

**App Sandbox is disabled** on purpose: a notch app needs system-level access the sandbox doesn't allow, so thenotch is distributed outside the Mac App Store. The hardened runtime is on.

## Releasing

1. Update `MARKETING_VERSION` in the project and add a section for the version to [CHANGELOG.md](CHANGELOG.md); merge it via a PR.
2. Tag `main` and push the tag:
   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```
3. The [Release workflow](.github/workflows/release.yml) runs the tests, builds the DMG and zip, signs the zip for Sparkle and writes `appcast.xml` (`scripts/make-appcast.sh`), then publishes a GitHub Release with that changelog section as notes. Installed copies find the update through `appcast.xml` on the latest release.

Each release needs a higher `CURRENT_PROJECT_VERSION` (build number) than the last: Sparkle compares it, not the marketing version.

### Update signing key (one-time setup)

Sparkle installs only updates signed with the private key whose public half is `SUPublicEDKey` in [Config/Info.plist](Config/Info.plist).

1. Generate the key pair. The private key is stored in your login Keychain, and the public key is printed:
   ```bash
   build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   The tool is there after any build that resolves packages (for example `scripts/build-release.sh`).
2. Put the public key in `SUPublicEDKey`.
3. Export the private key to a file, add the file's contents as the repository secret `SPARKLE_PRIVATE_KEY` (Settings › Secrets and variables › Actions), then delete the file:
   ```bash
   …/generate_keys -x sparkle-private-key.txt
   ```
4. Back the private key up, for example in a password manager. If it's lost, installed copies can't verify any future update.

## Project structure

```
thenotch/
├── App/        # Entry point (menu bar extra, Settings scene) and AppDelegate
├── Core/       # Island window, geometry, state, hover logic, module system
├── Modules/    # Features: NowPlaying, Battery, Shelf, HUD, Bluetooth, Notifications, ClaudeCode
└── Settings/   # Preferences and the Settings window
```

## License

[MIT](LICENSE) © 2026 Nguyễn Đình Đức

## Trademarks

thenotch is an independent project, not affiliated with or endorsed by Anthropic or Apple. Claude and Claude Code are trademarks of Anthropic; Spotify is a trademark of Spotify AB; Apple Music, AirPods and macOS are trademarks of Apple Inc. These names are used only to say which apps and devices thenotch works with.
