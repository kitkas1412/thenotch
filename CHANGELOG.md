# Changelog

All notable changes to thenotch are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Shelf**: drag files from Finder onto the notch to keep them at hand. The island opens as a drop target while you drag; click a file to open it, right-click to show it in Finder or remove it. The shelf lives in memory for now (cleared when you quit).
- Buttons beside the notch in the expanded island to switch between modules.
- Shelf: drag a file out of the shelf into Finder or any app (it's copied; the original stays put).
- AirDrop from the notch: while dragging files in, drop them on the **AirDrop** zone to send them right away, or use **AirDrop All** / right-click › AirDrop… on the shelf.

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
