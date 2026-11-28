import AppKit
import Testing
@testable import NotchANC

struct ParserTests {
    // Captured from bluetoothd on macOS 27.2 (trimmed).
    let dump = "2026-11-13 15:25:46.492 Df bluetoothd[67442:cee213] [com.apple.bluetooth:CBAccessoryDaemon] Connection monitor: CBDevice 7BA4, PrNm AirPods Pro, DvF 0x25885D80407F < AACP ANC Transparency >, LsnM Transparency, LsMC 0xE < ANC Transparency AutoANC >, BTv 6.0"

    @Test func deviceDump() {
        #expect(AirPodsMonitor.parse(dump) == .transparency)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM ANC")) == .noiseCancellation)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM NoiseCancellation")) == .noiseCancellation)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM AutoANC")) == .adaptive)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM Something")) == .other)
    }

    @Test func listeningModeNumbers() {
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 1") == .off)
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 2") == .noiseCancellation)
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 3") == .transparency)
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 4") == .adaptive)
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 9") == .other)
    }

    @Test func receivedListenMode() {
        #expect(AirPodsMonitor.parse("Received Listen mode 0x2 as ANC from device") == .noiseCancellation)
        #expect(AirPodsMonitor.parse("Received Listen mode 0x3 as Transparency from device") == .transparency)
    }

    @Test func unrelatedLine() {
        #expect(AirPodsMonitor.parse("bluetoothd: activating connection") == nil)
    }
}

struct NowPlayingTests {
    @Test func parse() {
        let t = Track.parse(#"{"playing":true,"title":"Somewhere Only We Know","artist":"Keane"}"#)
        #expect(t == Track(playing: true, title: "Somewhere Only We Know", artist: "Keane"))
        #expect(t?.text == "Somewhere Only We Know — Keane")
        #expect(Track.parse(#"{"playing":false,"title":"Podcast","artist":""}"#)?.text == "Podcast")
        #expect(Track.parse("{}") == nil)
        #expect(Track.parse(#"{"playing":true,"title":"","artist":"x"}"#) == nil)
    }

    @Test func position() {
        let t = Track.parse(#"{"playing":true,"title":"A","artist":"B","bundle":"com.apple.Music","elapsed":30,"duration":200,"timestamp":1000,"extra":1}"#)!
        #expect(t.bundle == "com.apple.Music" && t.duration == 200)
        #expect(t.position(at: Date(timeIntervalSince1970: 1012)) == 42)
        var paused = t
        paused.playing = false
        #expect(paused.position(at: Date(timeIntervalSince1970: 1012)) == 30)
        #expect(Track(playing: true, title: "A", artist: "").position(at: .now) == nil)
    }

    // Play/pause shows on the press: pausing stops the clock where it is, playing runs it on from there.
    @Test func toggled() {
        let t = Track(playing: true, title: "A", artist: "", elapsed: 30, duration: 200, timestamp: 1000)
        let paused = t.toggled(at: Date(timeIntervalSince1970: 1012))
        #expect(!paused.playing && paused.elapsed == 42 && paused.timestamp == 1012)
        #expect(paused.position(at: Date(timeIntervalSince1970: 1100)) == 42)
        let resumed = paused.toggled(at: Date(timeIntervalSince1970: 1100))
        #expect(resumed.playing && resumed.position(at: Date(timeIntervalSince1970: 1105)) == 47)
    }
}

struct MediaVisibilityTests {
    @Test func shows() {
        for playing in [false, true] {
            for toHeadphones in [false, true] {
                #expect(!MediaVisibility.never.shows(playing: playing, toHeadphones: toHeadphones))
                #expect(MediaVisibility.headphones.shows(playing: playing, toHeadphones: toHeadphones) == (playing && toHeadphones))
                #expect(MediaVisibility.anyOutput.shows(playing: playing, toHeadphones: toHeadphones) == playing)
                #expect(MediaVisibility.always.shows(playing: playing, toHeadphones: toHeadphones))
            }
        }
    }
}

struct GlanceTests {
    // system_profiler SPBluetoothDataType -json on macOS 27.2 (trimmed): levels come as "34%" strings.
    @Test func headphones() {
        let report = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Keyboard":{"device_minorType":"Keyboard"}},
          {"AirPods Pro":{"device_batteryLevelCase":"34%","device_batteryLevelLeft":"90%","device_batteryLevelRight":"100%"}}
        ],"device_not_connected":[{"Old Headset":{"device_batteryLevelMain":"50%"}}]}]}
        """
        let found = Glance.headphones(in: Data(report.utf8))
        #expect(found == Headphones(name: "AirPods Pro", left: 90, right: 100, charger: 34, main: nil))
        #expect(found?.level == 90)
        #expect(Glance.headphones(in: Data("{}".utf8)) == nil)
    }

    @Test func when() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = { (start: TimeInterval) in NextEvent(title: "Standup", start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + 1800)) }
        #expect(event(-600).when(at: now) == "Now")
        #expect(event(0).when(at: now) == "Now")
        #expect(event(30).when(at: now) == "in 1 min")
        #expect(event(12 * 60).when(at: now) == "in 12 min")
        #expect(event(59 * 60).when(at: now) == "in 59 min")
        #expect(event(60 * 60).when(at: now).hasPrefix("at "))
    }
}

struct CountdownTests {
    @Test func text() {
        #expect(Countdown.text(remaining: 25 * 60) == "25:00")
        #expect(Countdown.text(remaining: 59.2) == "1:00")
        #expect(Countdown.text(remaining: 0.4) == "0:01")
        #expect(Countdown.text(remaining: -3) == "0:00")
        #expect(Countdown.text(remaining: 3899) == "1:04:59")
    }
}

struct ColorTests {
    @Test func hexRoundTrip() {
        for hex in ["#FF9F0A", "#0A84FF", "#000000", "#FFFFFF"] { #expect(NSColor(hex: hex)?.hex == hex) }
        #expect(NSColor(hex: "FF9F0A") == nil && NSColor(hex: "#GGGGGG") == nil && NSColor(hex: "") == nil)
    }
}

struct LayoutTests {
    let screen = NSRect(x: 0, y: 0, width: 2056, height: 1329)

    // 14" MacBook Pro, measured: 2056pt wide, 38pt inset, 918pt auxiliary areas, a 220pt notch.
    @Test func notch() {
        let l = PillLayout(screen: screen, topInset: 38,
                           leftAux: NSRect(x: 0, y: 1291, width: 918, height: 38),
                           rightAux: NSRect(x: 1138, y: 1291, width: 918, height: 38), barHeight: 24)
        #expect(l.hasCutout && l.middle == 220 && l.cutoutName == "notch")
        #expect(l.bar == NSRect(x: 918 - 52, y: 1291, width: 52 + 220 + 52, height: 38))
        #expect(l.open == NSRect(x: 1028 - 300, y: 1291, width: 600, height: 38))
    }

    @Test func island() {
        let l = PillLayout(screen: screen, topInset: 38,
                           leftAux: NSRect(x: 0, y: 1291, width: 978, height: 38),
                           rightAux: NSRect(x: 1078, y: 1291, width: 978, height: 38), barHeight: 24)
        #expect(l.middle == 100 && l.cutoutName == "Dynamic Island")
        #expect(l.bar.minX == CGFloat(978 - 52) && l.bar.width == 204)
        #expect(l.open.midX == 1028)
    }

    // Built-in display placed right of a primary external one, cutout off the screen's midpoint.
    @Test func offCentreOnSecondaryScreen() {
        let l = PillLayout(screen: NSRect(x: 3440, y: 0, width: 2000, height: 1300), topInset: 38,
                           leftAux: NSRect(x: 3440, y: 1262, width: 800, height: 38),
                           rightAux: NSRect(x: 4440, y: 1262, width: 1000, height: 38), barHeight: 24)
        #expect(l.middle == 200)
        #expect(l.bar.minX == CGFloat(3440 + 800 - 52))
        #expect(l.bar.maxX == CGFloat(4440 + 52))
        #expect(l.open.midX == 4340)
    }

    // No cutout: a bar centred in the menu bar, at most 386pt wide, opening to the card's width.
    @Test func noCutout() {
        let l = PillLayout(screen: NSRect(x: 0, y: 0, width: 3440, height: 1440), topInset: 0,
                           leftAux: .zero, rightAux: .zero, barHeight: 24)
        #expect(!l.hasCutout && l.cutoutName == nil)
        #expect(l.bar == NSRect(x: 1720 - 193, y: 1416, width: 386, height: 24))
        #expect(l.open == NSRect(x: 1720 - 300, y: 1416, width: 600, height: 24))
    }

    // Without a cutout the bar hugs its content (16 edge, 20 icon, 12 gap) and stops growing at the widest text.
    @Test func barWidth() {
        #expect(PillLayout.barWidth(text: nil, trailing: nil) == 52)
        #expect(PillLayout.barWidth(text: 100, trailing: nil) == 164)
        #expect(PillLayout.barWidth(text: 100, trailing: 20) == 196)
        #expect(PillLayout.barWidth(text: nil, trailing: 32) == 96)
        #expect(PillLayout.barWidth(text: 1000, trailing: 20) == PillLayout.maxBar)
    }
}
