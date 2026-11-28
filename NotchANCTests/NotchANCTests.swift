import AppKit
import Testing
@testable import NotchANC

struct ParserTests {
    // Captured from bluetoothd on macOS 27.2 (trimmed).
    let dump = "2026-11-13 15:25:46.492 Df bluetoothd[67442:cee213] [com.apple.bluetooth:CBAccessoryDaemon] Connection monitor: CBDevice 7BA4, PrNm AirPods Pro, DvF 0x25885D80407F < AACP ANC Transparency >, LsnM Transparency, LsMC 0xE < ANC Transparency AutoANC >, BTv 6.0"

    @Test func deviceDump() {
        #expect(AirPodsMonitor.parse(dump) == false)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM ANC")) == true)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM NoiseCancellation")) == true)
        #expect(AirPodsMonitor.parse(dump.replacingOccurrences(of: "LsnM Transparency", with: "LsnM AutoANC")) == false)
    }

    @Test func listeningModeNumbers() {
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 2") == true)
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 3") == false)
        #expect(AirPodsMonitor.parse("bluetoothd: Listening Mode is set to 4") == false)
    }

    @Test func receivedListenMode() {
        #expect(AirPodsMonitor.parse("Received Listen mode 0x2 as ANC from device") == true)
        #expect(AirPodsMonitor.parse("Received Listen mode 0x3 as Transparency from device") == false)
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
        #expect(PillLayout.barWidth(text: nil, trailing: false) == 52)
        #expect(PillLayout.barWidth(text: 100, trailing: false) == 164)
        #expect(PillLayout.barWidth(text: 100, trailing: true) == 196)
        #expect(PillLayout.barWidth(text: 1000, trailing: true) == PillLayout.maxBar)
    }
}
