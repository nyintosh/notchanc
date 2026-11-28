# Development notes

How the parts fit, and the facts that are easy to get wrong. The README covers what the app does and how to build it.

## How the parts fit

- `NotchANC/App.swift`: menu, Sparkle, and `apply()`, which reacts to every UserDefaults change (keys `automatic`, `mediaVisibility`, `focusMinutes`, `focusStartShortcut`, `focusEndShortcut`, `menuBarIcon`, `hiddenDisplays`, `hideMenuBarIcon`, and per `PillMode` its `colorKey` hex and `iconKey` symbol). Reopening the app shows Settings.
- `NotchANC/Settings.swift`: Preferences window, an `NSTabViewController` (toolbar tabs) of SwiftUI forms that write UserDefaults directly.
- `NotchANC/Overlay.swift`: `PillLayout` (pure geometry, unit-tested) and one window per shown display. The window has the open card's size; only the pill view inside animates. Collapsed, the pill holds the playing app's icon (the state's icon with no track) and the visualizer, or a pause mark; without a cutout the track's text sits between and the bar hugs it. Hovering opens one card: status chips (Noise Cancellation on or off, the output device), the player when a track is loaded, and a row of tiles. The pill is black at the top and washed in the state's colour below. Hover uses mouse-moved event monitors. The window (a non-activating `NSPanel`) ignores clicks except while the pointer is on the pill, so right-click opens the status menu without stealing focus.
- `NotchANC/AudioTap.swift`: the visualizer's levels. A Core Audio process tap of the whole output feeds a private aggregate device; each 1024-sample block is split into five log bands, and each bar rests at half height on its band's running average. It runs only while a shown pill has something playing.
- `NotchANC/AudioOutput.swift`: the default output device's name and whether it is headphones; the pill's output chip and the "With headphones" choice both read it.
- `NotchANC/Glance.swift`: the tiles' readings, taken only while a pill is open: headphone battery from `system_profiler SPBluetoothDataType -json` (no public API has it), the Mac's battery from IOKit power sources, processor load from `host_statistics`.
- `NotchANC/Countdown.swift`: the quick timer and the focus session, one countdown at a time, started from the card's Timer tile. While it runs the pill stays up and its right end shows the time left; at the end it plays a sound and shows a bell until the card is opened. A focus session also runs the Shortcuts picked in Settings (`/usr/bin/shortcuts run`) when it starts and when it ends, since macOS has no API to switch Focus.
- `NotchANC/AirPodsMonitor.swift`: parses `bluetoothd` log lines (`LsnM <mode>` etc.); no public API exists.
- `NotchANC/NowPlaying.swift`: MediaRemote refuses non-Apple processes since macOS 15.4, so a JXA loop in Apple's `/usr/bin/osascript` reads `MRNowPlayingRequest` and prints JSON lines. It runs for the app's lifetime: `AppDelegate.updatePill()` picks `PillMode.anc` (accent colour) when ANC is on, else `.media` (blue) when `MediaVisibility` says so: never, while something plays into headphones (the default; `AudioOutput`: Bluetooth transport or the jack's 'hdpn' data source), while something plays into any output, or always. It hides 2 s after playback stops.

## Facts that are easy to get wrong

- Notch and Dynamic Island (PROLED XDR MacBook Pro, Oct 2026) both report through `safeAreaInsets.top` and `auxiliaryTopLeft/RightArea`. ActivityKit and WidgetKit `DynamicIsland` are unavailable on macOS (27.2 SDK), so apps cannot draw inside the island. `cutoutName` guesses notch versus island by width, which only affects the menu label.
- Not sandboxed: the app must spawn `/usr/bin/log`. Hardened runtime is on.
- SF Symbols are fine in the UI and menu bar, but not in the app icon (license). The icon is drawn in `tools/icon.swift`.
- Minimum macOS is 14.2, for the Core Audio process tap. Don't add `#available` branches.
- A MediaRemote command sent from osascript is dropped if osascript exits at once; `send()` waits half a second first.
- Clicking the player's track opens its app via osascript; for a browser it also selects the first tab whose title holds the track's title, since MediaRemote names only the app. Each browser family scripts tabs differently (`NowPlaying.tabFinders`); the bundle id is written into the script because a browser's terms resolve only at compile time.
- The player shows the playing app's icon, not the artwork: osascript reports the artwork's type and size but not its bytes.
- Never run the tests in a folder whose app was launched: macOS App Management then blocks writes into that signed bundle.
- Before a release, add the version's notes to `CHANGELOG.md`.
