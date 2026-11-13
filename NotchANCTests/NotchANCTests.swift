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
}

struct LayoutTests {
    let screen = NSRect(x: 0, y: 0, width: 2056, height: 1329)

    // 14" MacBook Pro, measured: 2056pt wide, 38pt inset, 918pt auxiliary areas, a 220pt notch.
    // 100pt text areas: each side opens to 48 + 100 + 10 = 158pt.
    @Test func notch() {
        let l = PillLayout(screen: screen, topInset: 38,
                           leftAux: NSRect(x: 0, y: 1291, width: 918, height: 38),
                           rightAux: NSRect(x: 1138, y: 1291, width: 918, height: 38), barHeight: 24, textWidth: 100)
        #expect(l.hasCutout && l.middle == 220 && l.cutoutName == "notch")
        #expect(l.window == NSRect(x: 918 - 158, y: 1291, width: 158 + 220 + 158, height: 38))
        #expect(l.collapsed == NSRect(x: 158 - 52, y: 0, width: 52 + 220 + 52, height: 38))
        #expect(l.expanded == NSRect(x: 0, y: 0, width: 536, height: 38))
        #expect(l.leftText == NSRect(x: 48, y: 0, width: 100, height: 38))
        #expect(l.rightText == NSRect(x: 536 - 148, y: 0, width: 100, height: 38))
    }

    @Test func island() {
        let l = PillLayout(screen: screen, topInset: 38,
                           leftAux: NSRect(x: 0, y: 1291, width: 978, height: 38),
                           rightAux: NSRect(x: 1078, y: 1291, width: 978, height: 38), barHeight: 24, textWidth: 100)
        #expect(l.middle == 100 && l.cutoutName == "Dynamic Island")
        #expect(l.window.minX == CGFloat(978 - 158))
    }

    // Built-in display placed right of a primary external one, cutout off the screen's midpoint.
    @Test func offCentreOnSecondaryScreen() {
        let l = PillLayout(screen: NSRect(x: 3440, y: 0, width: 2000, height: 1300), topInset: 38,
                           leftAux: NSRect(x: 3440, y: 1262, width: 800, height: 38),
                           rightAux: NSRect(x: 4440, y: 1262, width: 1000, height: 38), barHeight: 24, textWidth: 100)
        #expect(l.middle == 200)
        #expect(l.window.minX == CGFloat(3440 + 800 - 158))
        #expect(l.window.maxX == CGFloat(4440 + 158))
    }

    // No cutout: the original full pill, the same size collapsed and hovered, text between the icons.
    @Test func noCutout() {
        let l = PillLayout(screen: NSRect(x: 0, y: 0, width: 3440, height: 1440), topInset: 0,
                           leftAux: .zero, rightAux: .zero, barHeight: 24, textWidth: 100)
        #expect(!l.hasCutout && l.cutoutName == nil)
        #expect(l.window == NSRect(x: 1720 - 193, y: 1416, width: 48 + 290 + 48, height: 24))
        #expect(l.collapsed == l.expanded)
        #expect(l.leftText == NSRect(x: 48, y: 0, width: 290, height: 24) && l.rightText == l.leftText)
    }
}
