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

thenotch lives in the menu bar (capsule icon) and has no Dock icon. Use that menu for **Settings…**, **Check for Updates…** and **Quit thenotch**.

### Updating

From 0.3.0 on, thenotch updates itself with [Sparkle](https://sparkle-project.org): menu bar icon › **Check for Updates…**, or let it check once a day, which it does from the first launch (turn it off in Settings › Updates). Updates come from this repository's releases and are installed only if they're signed with the project's key. Versions before 0.3.0 need one manual update: download the new DMG and drag thenotch into Applications, replacing the old copy. Your shelf and settings are kept.

To verify a download, compare it with `SHA256SUMS.txt` from the release: `shasum -a 256 thenotch-<version>.dmg`.

### Permissions

- **Automation (Spotify / Music)** — requested the first time you use a playback control. If you decline, the track is still shown but the controls are replaced by a link to System Settings › Privacy & Security › Automation.
- Nothing else. thenotch doesn't need Accessibility, Screen Recording or Full Disk Access.

Because releases are not signed with a Developer ID, macOS may ask for the Automation permission again after you update.

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
├── Modules/    # Features: NowPlaying, Battery
└── Settings/   # Preferences and the Settings window
```

## License

[MIT](LICENSE) © 2026 Nguyễn Đình Đức
