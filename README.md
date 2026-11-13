# NotchANC

A menu bar app that shows a black pill around your MacBook's notch, or its Dynamic Island, while your AirPods are in Noise Cancellation.

- **Automatic.** NotchANC reads the AirPods listening mode from the system log, which needs no setup.
- **Now Playing.** Hover the pill and it slides open to show what's playing. The waveform moves only while media plays.
- **Any display.** It hugs the camera cutout on notch and Dynamic Island MacBooks and sits centred on other displays. Choose displays in **Settings › Appearance**.
- **Out of the way.** Clicks pass through the pill. On displays without a cutout, it hides while a full-screen app is in front.
- **Settings** has accent colours, Open at Login, automatic updates and **Hide menu bar icon**. With the icon hidden, open NotchANC again to reach Settings.

Requires macOS 14 or later. Download the latest DMG from [Releases](https://github.com/nyintosh/notchanc/releases).

## Scripting

Other tools can turn the pill on or off with a distributed notification:

```swift
DistributedNotificationCenter.default().postNotificationName(.init("notchanc.set"), object: "on", deliverImmediately: true)
```

While **Automatic** is on, the next AirPods mode change overrides the manual state.

## Building

Open `NotchANC.xcodeproj` in Xcode 27, or run:

```sh
xcodebuild -scheme NotchANC -derivedDataPath build/test test
```

`swift tools/icon.swift` redraws the app icon, and `tools/release.sh VERSION` publishes a notarized release.
