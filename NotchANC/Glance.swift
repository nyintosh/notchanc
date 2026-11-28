// What the idle card's tiles show: the headphones' battery and the Mac's battery and processor load.
// Read only while a pill is open.

import Foundation
import IOKit.ps

struct Headphones: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var charger: Int?   // the charging case
    var main: Int?      // headsets that report one level

    // The lowest of what's in the ears: the one that runs out first.
    var level: Int? { [left, right, main].compactMap { $0 }.min() }
}

struct MacStats: Equatable {
    var battery: Int?   // nil on a Mac without one
    var charging = false
    var processor = 0   // percent busy since the last reading
}

final class Glance: ObservableObject {
    @Published private(set) var headphones: Headphones?
    @Published private(set) var mac = MacStats()
    private var timer: Timer?
    private var ticks: (busy: UInt64, total: UInt64)?
    private var readings = 0

    var isWatching = false {
        didSet {
            guard isWatching != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard isWatching else { return }
            readings = 0
            read()
            timer = .scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.read() }
        }
    }

    init() { ticks = Self.processorTicks() }   // a baseline, so the first reading covers real time

    private func read() {
        var mac = Self.power()
        let now = Self.processorTicks()
        if let now, let ticks, now.total > ticks.total {
            mac.processor = Int((Double(now.busy - ticks.busy) / Double(now.total - ticks.total) * 100).rounded())
        } else {
            mac.processor = self.mac.processor
        }
        ticks = now
        if mac != self.mac { self.mac = mac }
        // Battery levels move slowly: every 30 seconds is plenty.
        if readings % 15 == 0 { readHeadphones() }
        readings += 1
    }

    // ponytail: no public API gives AirPods battery levels; system_profiler's report does, in about 0.1 s.
    private func readHeadphones() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let found = Self.headphones(in: pipe.fileHandleForReading.readDataToEndOfFile())
            DispatchQueue.main.async {
                guard let self, found != self.headphones else { return }
                self.headphones = found
            }
        }
    }

    // The first connected device that reports a battery level.
    static func headphones(in report: Data) -> Headphones? {
        guard let root = try? JSONSerialization.jsonObject(with: report) as? [String: Any],
              let bluetooth = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = bluetooth["device_connected"] as? [[String: Any]] else { return nil }
        for entry in connected {
            for (name, value) in entry {
                guard let device = value as? [String: Any] else { continue }
                let level = { (key: String) in (device[key] as? String).flatMap { Int($0.dropLast()) } }   // "34%"
                let found = Headphones(name: name, left: level("device_batteryLevelLeft"), right: level("device_batteryLevelRight"),
                                       charger: level("device_batteryLevelCase"), main: level("device_batteryLevelMain"))
                if found.level != nil { return found }
            }
        }
        return nil
    }

    private static func power() -> MacStats {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let full = d[kIOPSMaxCapacityKey] as? Int, full > 0 else { continue }
            return MacStats(battery: now * 100 / full, charging: d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return MacStats()
    }

    private static func processorTicks() -> (busy: UInt64, total: UInt64)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = load.cpu_ticks   // user, system, idle, nice
        let busy = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)
        return (busy, busy + UInt64(t.2))
    }
}
