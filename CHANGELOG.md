# Changelog

All notable changes to thenotch are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Shelf**: drag files from Finder onto the notch to keep them at hand. The island opens as a drop target while you drag; click a file to select it, double-click to open it, right-click to show it in Finder or remove it.
- Shelf: drag a file out of the shelf into a Finder folder to move it there, like Cut + Paste: it leaves its old place and the shelf. Across disks Finder copies instead (hold ⌘ to move, ⌥ to copy); dropping into an app such as Mail attaches a copy and keeps it on the shelf.
- The shelf is kept across launches and follows files you rename or move. Files leave it after 1 hour, 1 day (default), 1 week or never (Settings › Shelf).
- Images, PDFs, videos and audio dragged from apps (Safari, Photos, Mail…) can be dropped too; thenotch saves a copy and deletes it when it leaves the shelf.
- AirDrop from the notch: while dragging files in, drop them on the **AirDrop** zone to send them right away, or use **AirDrop All…** / right-click › AirDrop… on the shelf. Selecting a file shows Show in Finder, AirDrop… and Remove above the shelf.
- Now Playing: a new player with large artwork, a progress bar, a level meter tinted with the artwork's color, and an audio output picker (built-in speakers, headphones, AirPlay…).
- Now Playing: a star to add the track to Favorites in Apple Music (Spotify doesn't allow other apps to do this).

### Changed

- Hovering the notch opens the island only when there's something to show: a playing or paused track, files on the shelf, or a battery alert. Otherwise the notch is left alone.
- Accessibility: every control has a VoiceOver label, controls are at least 28 × 28 pt, the island follows Reduce Motion (a short fade instead of the spring, still level meter) and Increase Contrast, and text is larger and heavier.
- A consistent look across the island, following a documented design system (`DESIGN.md`): one type scale, spacing on a 4 pt grid, equal padding between the content and the island's edge (24 pt when open, and around the wings beside the notch, which are now only as wide as their content), corners concentric with the island, and fills and outlines that get stronger with Increase Contrast.
- When more than one thing is going on, such as music playing and files on the shelf, tabs beside the notch switch between them. With only one, the island shows no tabs.
- The island's content opens and closes with the island: it is revealed as the island grows and covered as it shrinks, instead of fading out outside it.

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

[Unreleased]: https://github.com/kitkas1412/thenotch/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kitkas1412/thenotch/releases/tag/v0.1.0
