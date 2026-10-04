# Changelog

All notable changes to thenotch are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.5.0] - 2026-10-04

### Added

- Bluetooth: AirPods and other Bluetooth devices peek beside the notch when they connect, or when the sound switches to them (taking AirPods out of their case), with their battery; open the island for each AirPod and the case. macOS still shows its own AirPods card below the notch. Turn it on in Settings › Modules; it needs Bluetooth access, which thenotch asks for then.
- Volume & Brightness: the volume, mute and brightness keys show a small level bar beside the notch instead of the macOS overlay. Turn it on in Settings › Modules; it needs Accessibility access, which thenotch asks for then. Shift-Option with the keys changes the level in smaller steps, as in macOS.
- Player: click or drag along the progress bar to jump to another part of the track, in Spotify and Music. The time follows the pointer while you drag; the track moves when you let go. With VoiceOver, swipe up or down to skip 10 seconds.

## [0.4.1] - 2026-10-04

### Changed

- Checks for updates once a day from the first launch, instead of asking on the second launch whether to. Turn it off in Settings › Updates; if you already chose there or in that prompt, your choice is kept.

## [0.4.0] - 2026-10-04

### Changed

- Shelf: opens as a small square, like Dropover, with the newest files stacked on top of each other. Drag the stack to take every file at once, click "Show All" to widen the island to every file, ✕ to clear the shelf, or … for AirDrop and Show in Finder. While the shelf is empty, a small AirDrop zone in the corner sends dropped files right away. When music is playing, switching between its tab and the shelf's resizes the island; the tabs move under the notch while the shelf's square is shown.
- Dropping files: the whole island is the drop target. Its border turns thick and white when files are over it, and the shelf just says "Drop here" instead of showing dashed drop zones.
- Shelf list ("Show All"): files no longer highlight under the pointer; only the selected file is highlighted, as in Finder, and clicking anywhere else in the list clears the selection.
- Shelf: a file dragged out and dropped anywhere leaves the shelf, including apps that take a copy (uploading to Google Drive in a browser, attaching it in Mail, a chat). The file itself stays where it was. Cancelling the drag keeps it on the shelf.
- Switching tabs slides the content over to the next tab, toward its side, instead of fading to a new view. With Reduce Motion on, it still fades.

## [0.3.2] - 2026-10-04

### Changed

- Uses less energy: the level meter beside the notch stands still while the display sleeps, the screen is locked, another user is logged in, or Low Power Mode is on.
- The shelf is saved in the background, a moment after it changes, instead of on every change; nothing is lost when you quit.
- Faster launch: the shelf is read in the background instead of holding up the island.
- Opening the island shows shelf thumbnails right away: they're kept instead of being made again each time.
- Album artwork is decoded at the size it's shown, off the main thread.

## [0.3.1] - 2026-10-04

The first version you can get with **Check for Updates…** from 0.3.0.

### Fixed

- Shelf: dropping files on the **AirDrop** zone while dragging them in now sends them with AirDrop; before, they ended up on the shelf. Drops on **Keep on Shelf** are taken across the whole zone.

## [0.3.0] - 2026-10-03

### Added

- **Check for Updates…** in the menu bar menu, and automatic daily update checks (Settings › Updates), with [Sparkle](https://sparkle-project.org). Updates are verified with the project's signing key before they're installed. This version still has to be installed by hand once; later versions update themselves.

### Known limitations

- Still not notarized: macOS asks you to allow the app once, and may ask for Automation permission again after an update.

## [0.2.0] - 2026-10-03

### Added

- **Shelf**: drag files from Finder onto the notch to keep them at hand. The island opens as a drop target while you drag; click a file to select it, double-click to open it, right-click to show it in Finder or remove it.
- Shelf: drag a file out of the shelf into a Finder folder to move it there, like Cut + Paste: it leaves its old place and the shelf. Across disks Finder copies instead (hold ⌘ to move, ⌥ to copy); dropping into an app such as Mail attaches a copy and keeps it on the shelf.
- The shelf is kept across launches and follows files you rename or move. Files leave it after 1 hour, 1 day (default), 1 week or never (Settings › Shelf).
- Images, PDFs, videos and audio dragged from apps (Safari, Photos, Mail…) can be dropped too; thenotch saves a copy and deletes it when it leaves the shelf.
- AirDrop from the notch: while dragging files in, drop them on the **AirDrop** zone to send them right away, or use **AirDrop All…** / right-click › AirDrop… on the shelf. Selecting a file shows Show in Finder, AirDrop… and Remove above the shelf.
- Now Playing: a new player with large artwork, a progress bar, a level meter tinted with the artwork's color, and an audio output picker (built-in speakers, headphones, AirPlay…).
- Now Playing: a star to add the track to Favorites in Apple Music (Spotify doesn't allow other apps to do this).
- When more than one thing is going on, such as music playing and files on the shelf, tabs beside the notch switch between them. With only one, the island shows no tabs.

### Changed

- Hovering the notch opens the island only when there's something to show: a playing or paused track, files on the shelf, or a battery alert. Otherwise the notch is left alone.
- Accessibility: every control has a VoiceOver label, controls are at least 28 × 28 pt, the island follows Reduce Motion (a short fade instead of the spring, still level meter) and Increase Contrast, and text is larger and heavier.
- A consistent look across the island, following a documented design system (`DESIGN.md`): one type scale, spacing on a 4 pt grid, equal padding between the content and the island's edge (24 pt when open, and around the wings beside the notch, which are now only as wide as their content), corners concentric with the island, and fills and outlines that get stronger with Increase Contrast.
- The island's content opens and closes with the island: it is revealed as the island grows and covered as it shrinks, instead of fading out outside it.

### Known limitations

- Still not notarized: macOS asks you to allow the app once, and may ask for Automation permission again after an update.
- Favorites work only with Apple Music; Now Playing still supports only Spotify and Apple Music.

## [0.1.0] - 2026-10-03

First public release (MVP).

### Added

- A black island over the MacBook notch that expands when you hover over it, with spring animations. Macs without a notch get a simulated notch centered under the menu bar.
- The island follows display changes (plugging in a monitor, changing resolution) and never blocks clicks on the menu bar while closed.
- **Now Playing** for Spotify and Apple Music: artwork and a level meter beside the notch while music plays; title, artist, progress and previous / play-pause / next controls when expanded.
- **Battery**: a short peek when you plug in or unplug the charger, or the battery drops to 20% or 10%.
- Settings window (menu bar icon › Settings…): turn modules on or off, launch at login.

### Known limitations

- Not notarized (no paid Apple Developer ID yet): macOS asks you to allow the app once, and may ask for Automation permission again after an update.
- Now Playing supports only Spotify and Apple Music (not browsers or other players).

[Unreleased]: https://github.com/kitkas1412/thenotch/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/kitkas1412/thenotch/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/kitkas1412/thenotch/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/kitkas1412/thenotch/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/kitkas1412/thenotch/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/kitkas1412/thenotch/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/kitkas1412/thenotch/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kitkas1412/thenotch/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kitkas1412/thenotch/releases/tag/v0.1.0
