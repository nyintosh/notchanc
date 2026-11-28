// What the card reads from the system: the headphones' battery for the output chip, and for the tiles the next
// calendar event and how busy the Mac is (processor, graphics, memory, disk). Read only while a pill is open.

import EventKit
import Foundation
import IOKit

struct Headphones: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var charger: Int?   // the charging case
    var main: Int?      // headsets that report one level

    // The lowest of what's in the ears: the one that runs out first.
    var level: Int? { [left, right, main].compactMap { $0 }.min() }
}

struct NextEvent: Equatable {
    var title: String
    var start: Date
    var end: Date

    // "Now" once it has started, minutes inside the hour before, otherwise its time.
    func when(at now: Date) -> String {
        if start <= now { return "Now" }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes < 60 ? "in \(minutes) min" : "at \(start.formatted(date: .omitted, time: .shortened))"
    }
}

// Percentages. A reading the Mac won't give is left out of the tile.
struct MacStats: Equatable {
    var processor = 0   // busy since the last reading
    var graphics: Int?
    var memory: Int?
    var disk: Int?
}

final class Glance: ObservableObject {
    @Published private(set) var headphones: Headphones?
    @Published private(set) var mac = MacStats()
    @Published private(set) var event: NextEvent?
    @Published private(set) var calendar = EKEventStore.authorizationStatus(for: .event)
    private let store = EKEventStore()
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
        var mac = MacStats(graphics: Self.graphics(), memory: Self.memory(), disk: self.mac.disk)
        let now = Self.processorTicks()
        if let now, let ticks, now.total > ticks.total {
            mac.processor = Int((Double(now.busy - ticks.busy) / Double(now.total - ticks.total) * 100).rounded())
        } else {
            mac.processor = self.mac.processor
        }
        ticks = now
        // Battery levels, the calendar and the disk move slowly: every 30 seconds is plenty.
        if readings % 15 == 0 { mac.disk = Self.disk() }
        if mac != self.mac { self.mac = mac }
        if readings % 15 == 0 {
            readHeadphones()
            readEvent()
        }
        readings += 1
    }

    // Asked from the tile's own button, the first time the user wants it.
    func askForCalendar() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.calendar = EKEventStore.authorizationStatus(for: .event)
                self?.readEvent()
            }
        }
    }

    // The next timed event in the coming day; one under way counts until it ends.
    private func readEvent() {
        guard calendar == .fullAccess else { return }
        let now = Date()
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil))
        let next = events.filter { !$0.isAllDay && $0.endDate > now }.min { $0.startDate < $1.startDate }
            .map { NextEvent(title: $0.title ?? "", start: $0.startDate, end: $0.endDate) }
        if next != event { event = next }
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

    // ponytail: no public API reports GPU load; the graphics driver publishes it in the I/O Registry under this name.
    private static func graphics() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Int?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            if let load = statistics?["Device Utilization %"] as? Int { busiest = max(busiest ?? 0, load) }
        }
        return busiest
    }

    // Memory in use the way Activity Monitor counts it: apps' own pages, wired and compressed, out of what's installed.
    private static func memory() -> Int? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(info.internal_page_count) - UInt64(info.purgeable_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        return percent(pages * UInt64(vm_kernel_page_size), of: ProcessInfo.processInfo.physicalMemory)
    }

    // How full the startup disk is, counting space macOS can free on demand as free.
    private static func disk() -> Int? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = values?.volumeTotalCapacity, let free = values?.volumeAvailableCapacityForImportantUsage, total > 0 else { return nil }
        return percent(UInt64(total) - UInt64(min(free, Int64(total))), of: UInt64(total))
    }

    static func percent(_ part: UInt64, of whole: UInt64) -> Int {
        whole == 0 ? 0 : Int((Double(min(part, whole)) / Double(whole) * 100).rounded())
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
