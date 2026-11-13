# NotchANC

Menu bar app (LSUIElement, AppKit, no SwiftUI) that draws a pill beside the camera cutout while AirPods are in Noise Cancellation.

- `NotchANC/App.swift`: menu, Sparkle, and `apply()`, which reacts to every UserDefaults change (keys `automatic`, `showMedia`, `hiddenDisplays`, `hideMenuBarIcon`, and per `PillMode` its `colorKey` hex and `iconKey` symbol). Reopening the app shows Settings.
- `NotchANC/Settings.swift`: Preferences window, an `NSTabViewController` (toolbar tabs) of SwiftUI forms that write UserDefaults directly.
- `NotchANC/Overlay.swift`: `PillLayout` (pure geometry, unit-tested) and one window per shown display. The window has the expanded size; only the pill view inside animates. Beside a cutout, expanded = ANC label left, Now Playing right, both as wide as the ANC label. Without a cutout the pill is the original full marquee and hovering swaps in Now Playing at the same size. Hover uses mouse-moved event monitors. The window (a non-activating `NSPanel`) ignores clicks except while the pointer is on the pill, so right-click opens the status menu without stealing focus.
- `NotchANC/AirPodsMonitor.swift`: parses `bluetoothd` log lines (`LsnM <mode>` etc.); no public API exists.
- `NotchANC/NowPlaying.swift`: MediaRemote refuses non-Apple processes since macOS 15.4, so a JXA loop in Apple's `/usr/bin/osascript` reads `MRNowPlayingRequest` and prints JSON lines. Runs for the app's lifetime: `AppDelegate.updatePill()` picks `PillMode.anc` (accent colour) when ANC is on, else `.media` (blue) while something plays into headphones (`AudioOutput`: Bluetooth transport or the jack's 'hdpn' data source), hiding 2 s after playback stops.

## Facts that are easy to get wrong
- Notch and Dynamic Island (PROLED XDR MacBook Pro, Oct 2026) both report through `safeAreaInsets.top` and `auxiliaryTopLeft/RightArea`. ActivityKit and WidgetKit `DynamicIsland` are unavailable on macOS (27.2 SDK), so apps cannot draw inside the island. `cutoutName` guesses notch versus island by width, which only affects the menu label.
- Not sandboxed: the app must spawn `/usr/bin/log`. Hardened runtime is on.
- SF Symbols are fine in the UI and menu bar, but not in the app icon (license). The icon is drawn in `tools/icon.swift`.
- Minimum macOS is 14. Don't add `#available` branches.

## Build, test, release
- Test: `xcodebuild -scheme NotchANC -derivedDataPath build/test test`. Never test in a folder whose app was launched: macOS App Management then blocks writes into that signed bundle.
- Release: `tools/release.sh VERSION`. It archives, exports with Developer ID (team BC8RBD2A8Y), notarizes with the App Store Connect API key, staples a DMG, appends to `appcast.xml` (Sparkle key account `notchanc` in the login keychain), tags, pushes and creates the GitHub release. Add the version's notes to `CHANGELOG.md` first. Commits and tags are SSH-signed with `~/.ssh/nyintosh` as `56629705+nyintosh@users.noreply.github.com`; never add a co-author line.
- GitHub: `nyintosh/notchanc` (public). Push with `~/.ssh/nyintosh` (repo `core.sshCommand`).
