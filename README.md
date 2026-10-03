# thenotch

A free, open-source macOS app that turns the MacBook notch into an interactive "Dynamic Island", inspired by [DynamicLake](https://dynamiclake.com).

> **Status:** v0.1 — first public release (MVP). Expect rough edges; [bug reports](https://github.com/kitkas1412/thenotch/issues) are welcome.

## Features

- **Island over the notch** — expands when you rest the pointer on it and closes when you move away. It never blocks the menu bar while closed.
- **Now Playing** — artwork and a level meter beside the notch while Spotify or Apple Music plays; title, artist, progress and playback controls when expanded.
- **Battery** — a short peek when you plug in or unplug the charger, or the battery drops to 20% / 10%.
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

thenotch lives in the menu bar (capsule icon) and has no Dock icon. Use that menu for **Settings…** and **Quit thenotch**.

To verify a download, compare it with `SHA256SUMS.txt` from the release: `shasum -a 256 thenotch-<version>.dmg`.

### Permissions

- **Automation (Spotify / Music)** — requested the first time you use a playback control. If you decline, the track is still shown but the controls are replaced by a link to System Settings › Privacy & Security › Automation.
- Nothing else. thenotch doesn't need Accessibility, Screen Recording or Full Disk Access.

Because releases are not signed with a Developer ID, macOS may ask for the Automation permission again after you update.

## Privacy

thenotch runs entirely on your Mac. It collects no data and sends nothing over the network; the only network request is downloading album artwork from Spotify's image server for the track that is playing.

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
3. The [Release workflow](.github/workflows/release.yml) runs the tests, builds the DMG and zip, and publishes a GitHub Release with that changelog section as notes.

## Project structure

```
thenotch/
├── App/        # Entry point (menu bar extra, Settings scene) and AppDelegate
├── Core/       # Island window, geometry, state, hover logic, module system
├── Modules/    # Features: NowPlaying, Battery
└── Settings/   # Preferences and the Settings window
```

## License

[MIT](LICENSE) © 2026 Nguyễn Đình Đức
