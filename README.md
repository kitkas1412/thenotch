# thenotch

A macOS app that turns the MacBook notch into an interactive "Dynamic Island", inspired by [DynamicLake](https://dynamiclake.com).

> **Status:** early development. The project structure is in place; island features are not implemented yet.

## Requirements

- macOS 14.0 or later
- A Mac with a notch (a fallback for non-notch displays is planned)
- Xcode 27 or later to build

## Building

1. Clone the repository and open `thenotch.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your own development team.
3. Run the `thenotch` scheme (⌘R).

Or build from the command line:

```bash
xcodebuild -project thenotch.xcodeproj -scheme thenotch -configuration Debug build
```

The app runs as an agent (`LSUIElement`): it has no Dock icon and no main window. To quit it during development, run `killall thenotch`.

## Project structure

```
thenotch/
├── App/                 # App entry point and AppDelegate
└── Core/
    ├── Geometry/        # Notch position and size from NSScreen
    ├── State/           # Observable island state
    ├── UI/              # SwiftUI island view and notch shape
    └── Window/          # NSPanel hosting the island, and its controller
```

## Notes

- **App Sandbox is disabled.** A notch app needs system-level access that the sandbox does not allow, so thenotch will be distributed outside the Mac App Store.
- Hardened Runtime is enabled so that builds can be notarized.
