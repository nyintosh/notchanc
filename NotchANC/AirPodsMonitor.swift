// macOS has no public API for the AirPods listening mode, but bluetoothd logs every change,
// e.g. "Listening Mode is set to 2" (1 Off, 2 Noise Cancellation, 3 Transparency, 4 Adaptive)
// and "... LsnM ANC ..." inside its device dumps. We read that log:
//   - on start / reconnect: `log show` for the last 30 minutes (current state)
//   - afterwards: a live `log stream`

import Foundation
import IOBluetooth

final class AirPodsMonitor: NSObject {
    var onChange: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    private var proc: Process?
    private var buffer = Data()
    private var timer: Timer?
    private var running = false
    private var wasConnected: Bool?

    private let predicate = "process == \"bluetoothd\" AND (eventMessage CONTAINS \"LsnM\" OR eventMessage CONTAINS \"Listening Mode is set to\" OR eventMessage CONTAINS \"Received Listen mode\")"

    func start() {
        stop()
        running = true
        backfill()
        stream()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkConnection() }
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        proc?.terminationHandler = nil
        proc?.terminate(); proc = nil
        buffer.removeAll()
        wasConnected = nil
    }

    // true = Noise Cancellation, false = any other mode, nil = line not understood
    static func parse(_ line: String) -> Bool? {
        if let r = line.range(of: "Listening Mode is set to ") {
            let digits = line[r.upperBound...].prefix(while: { $0.isNumber })
            if let n = Int(digits) { return n == 2 }
        }
        if let r = line.range(of: "Received Listen mode"), let asR = line.range(of: " as ", range: r.upperBound..<line.endIndex) {
            let word = line[asR.upperBound...].prefix(while: { $0.isLetter })
            return word == "ANC"
        }
        if let r = line.range(of: "LsnM ") {
            let word = line[r.upperBound...].prefix(while: { $0.isLetter })
            if word.isEmpty { return nil }
            return word == "ANC" || word.hasPrefix("NoiseC")
        }
        return nil
    }

    private func backfill() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            p.arguments = ["show", "--last", "30m", "--style", "compact", "--predicate", self.predicate]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            var state: Bool?
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if let v = Self.parse(String(line)) { state = v }
            }
            if let state {
                DispatchQueue.main.async { if self.running { self.onChange?(state) } }
            }
        }
    }

    private func stream() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "compact", "--predicate", predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                self.onStatus?("AirPods: log stream stopped, retrying…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if self.running { self.stream() } }
            }
        }
        do {
            try p.run()
            proc = p
            onStatus?("AirPods: watching ✓")
        } catch {
            onStatus?("AirPods: can't read system log")
        }
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let v = Self.parse(String(decoding: lineData, as: UTF8.self)) { onChange?(v) }
        }
    }

    // Hide the indicator when the headphones disconnect; re-read the state when they come back.
    // Matched by device class, not name, so renamed AirPods still count.
    private func checkConnection() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard !devices.isEmpty else { return }   // no list (e.g. permission denied): don't guess
        let connected = devices.contains { $0.isConnected() && $0.deviceClassMajor == kBluetoothDeviceClassMajorAudio }
        if connected != wasConnected {
            if connected { backfill() } else { onChange?(false); onStatus?("AirPods: not connected") }
            wasConnected = connected
        }
    }
}
