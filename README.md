# NotchANC

A menu bar app that shows a black pill around your MacBook's notch, or its Dynamic Island, while your AirPods are in Noise Cancellation.

- **Automatic.** NotchANC reads the AirPods listening mode from the system log, which needs no setup.
- **Any display.** It hugs the camera cutout on notch and Dynamic Island MacBooks and sits centred on other displays. Choose displays under **Show On**.
- **Out of the way.** On displays without a cutout, the pill hides while a full-screen app is in front.
- **Accent colours**, **Launch at Login** and automatic updates are built in.

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
xcodebuild -scheme NotchANC -derivedDataPath build/dd test
```

`swift tools/icon.swift` redraws the app icon, and `tools/release.sh VERSION` publishes a notarized release.
