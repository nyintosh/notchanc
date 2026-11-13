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

struct LayoutTests {
    // 14" MacBook Pro, measured: 2056pt wide, 38pt inset, 918pt auxiliary areas, a 220pt notch.
    @Test func notch() {
        let l = PillLayout(screen: NSRect(x: 0, y: 0, width: 2056, height: 1329), topInset: 38,
                           leftAux: NSRect(x: 0, y: 1291, width: 918, height: 38),
                           rightAux: NSRect(x: 1138, y: 1291, width: 918, height: 38), barHeight: 24)
        #expect(l.hasCutout && l.middle == 220 && l.cutoutName == "notch")
        #expect(l.frame == NSRect(x: 918 - 52, y: 1291, width: 52 + 220 + 168, height: 38))
    }

    @Test func island() {
        let l = PillLayout(screen: NSRect(x: 0, y: 0, width: 2056, height: 1329), topInset: 38,
                           leftAux: NSRect(x: 0, y: 1291, width: 978, height: 38),
                           rightAux: NSRect(x: 1078, y: 1291, width: 978, height: 38), barHeight: 24)
        #expect(l.middle == 100 && l.cutoutName == "Dynamic Island")
        #expect(l.frame.minX == CGFloat(978 - 52))
    }

    // Built-in display placed right of a primary external one, cutout off the screen's midpoint.
    @Test func offCentreOnSecondaryScreen() {
        let l = PillLayout(screen: NSRect(x: 3440, y: 0, width: 2000, height: 1300), topInset: 38,
                           leftAux: NSRect(x: 3440, y: 1262, width: 800, height: 38),
                           rightAux: NSRect(x: 4440, y: 1262, width: 1000, height: 38), barHeight: 24)
        #expect(l.middle == 200)
        #expect(l.frame.minX == CGFloat(3440 + 800 - 52))
    }

    @Test func noCutout() {
        let l = PillLayout(screen: NSRect(x: 0, y: 0, width: 3440, height: 1440), topInset: 0,
                           leftAux: .zero, rightAux: .zero, barHeight: 24)
        #expect(!l.hasCutout && l.cutoutName == nil)
        #expect(l.frame == NSRect(x: 1720 - 145 - 48, y: 1416, width: 48 + 290 + 48, height: 24))
    }
}
