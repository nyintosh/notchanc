# NotchANC

Menu bar app (LSUIElement, AppKit, no SwiftUI) that draws a pill beside the camera cutout while AirPods are in Noise Cancellation.

- `NotchANC/App.swift`: menu, settings (UserDefaults keys `automatic`, `accentColor`, `hiddenDisplays`), Sparkle.
- `NotchANC/Overlay.swift`: `PillLayout` (pure geometry, unit-tested) and one window per shown display.
- `NotchANC/AirPodsMonitor.swift`: parses `bluetoothd` log lines (`LsnM <mode>` etc.); no public API exists.

## Facts that are easy to get wrong
- Notch and Dynamic Island (PROLED XDR MacBook Pro, Oct 2026) both report through `safeAreaInsets.top` and `auxiliaryTopLeft/RightArea`. ActivityKit and WidgetKit `DynamicIsland` are unavailable on macOS (27.2 SDK), so apps cannot draw inside the island. `cutoutName` guesses notch versus island by width, which only affects the menu label.
- Not sandboxed: the app must spawn `/usr/bin/log`. Hardened runtime is on.
- SF Symbols are fine in the UI and menu bar, but not in the app icon (license). The icon is drawn in `tools/icon.swift`.
- Minimum macOS is 14. Don't add `#available` branches.

## Build, test, release
- Test: `xcodebuild -scheme NotchANC -derivedDataPath build/dd test`.
- Release: `tools/release.sh VERSION`. It archives, exports with Developer ID (team BC8RBD2A8Y), notarizes with the App Store Connect API key, staples a DMG, appends to `appcast.xml` (Sparkle key account `notchanc` in the login keychain), tags, pushes and creates the GitHub release. Add the version's notes to `CHANGELOG.md` first.
- GitHub: `nyintosh/notchanc` (public). Push with `~/.ssh/nyintosh` (repo `core.sshCommand`).
