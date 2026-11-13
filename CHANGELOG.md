# Changelog

## [1.0.4]
- **Customise each state.** Settings › Appearance now sets the colour and icon separately for Noise Cancellation and for Now Playing, with ten preset colours plus a picker for any colour. The menu bar icon follows the Noise Cancellation icon.
- The blue Now Playing pill can be turned off.
- Your previous accent colour carries over to Noise Cancellation.

## [1.0.3]
- **Now Playing without ANC.** When Noise Cancellation is off but something is playing through headphones (AirPods, any Bluetooth headset, or the headphone jack), the pill appears in blue with a music note list, "Now Playing" and the moving waveform. On displays without a notch it shows the current track directly. It hides two seconds after playback stops, so it doesn't flash between tracks.
- The Noise Cancellation pill and menu bar icon use a moon (quiet, like Do Not Disturb) instead of the AirPods glyph.
- **Right-click the pill** for the same menu as the menu bar icon: Settings, Check for Updates, Quit and the Noise Cancellation toggles. Handy with the menu bar icon hidden. Clicking the pill never takes focus from the app you're using.
- If Now Playing can't be read (for example on an older macOS), NotchANC retries less and less often instead of every few seconds.
- New README with screenshots, install steps and how it works. NotchANC is now MIT licensed.

## [1.0.2]
- Hovering opens the pill evenly on both sides: "Noise Cancellation On" on the left and the current track on the right, at the same width. Long titles scroll instead of widening the pill.
- On displays without a notch or Dynamic Island, the pill is back to its full scrolling "Noise Cancellation On" form; hovering swaps it for the current track.
- Titles in Myanmar, Thai and other tall scripts are no longer cut off at the bottom.

## [1.0.1]
- **Hover to see Now Playing.** The pill now stays compact: AirPods icon, notch, waveform. Hover it and the left side slides open to show the current track, or "Noise Cancellation On" when nothing is loaded.
- The waveform moves only while media is playing.
- **Settings window** with General, Appearance and About tabs. Choose ⌘, from the menu.
- **Hide menu bar icon.** Open NotchANC again to bring up Settings.
- Display choice, accent colour and Open at Login moved from the menu into Settings.

## [1.0.0]
- First signed and notarized release.
- **Show On**: pick which displays show the pill. New displays show it by default.
- The pill hugs the camera cutout on notch and Dynamic Island MacBooks, wherever the display sits in your arrangement.
- On displays without a cutout, the pill hides behind full-screen apps.
- Settings now survive relaunches: accent colour, Automatic and displays.
- Renamed AirPods are recognised.
- Automatic updates via **Check for Updates…**.
- New app icon.
