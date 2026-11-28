// The quick timer and the focus session: one countdown at a time, started from the card's Timer tile.
// A focus session also runs the Shortcuts picked in Settings when it starts and when it ends,
// since macOS has no API to switch Focus.

import AppKit

struct Session: Equatable {
    var end: Date
    var focus: Bool
}

final class Countdown: ObservableObject {
    static let presets = [5, 15, 25]   // minutes
    static let focusMinutesKey = "focusMinutes"
    static let focusLengths = [25, 50]
    static let startShortcutKey = "focusStartShortcut"
    static let endShortcutKey = "focusEndShortcut"
    private static let sound = NSSound.Name("Glass")

    @Published private(set) var session: Session?
    @Published private(set) var rang = false   // finished, and the card not opened since
    var onChange: (() -> Void)?
    private var timer: Timer?

    // The pill stays up while there is something to count or to tell.
    var isActive: Bool { session != nil || rang }

    func start(minutes: Int, focus: Bool) {
        stop()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        session = Session(end: end, focus: focus)
        rang = false
        timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.ring() }
        RunLoop.main.add(timer!, forMode: .common)
        if focus { Self.run(shortcut: Self.startShortcutKey) }
        onChange?()
    }

    func startFocus() { start(minutes: UserDefaults.standard.integer(forKey: Self.focusMinutesKey), focus: true) }

    func cancel() {
        stop()
        onChange?()
    }

    // Opening the card is how the user answers the bell.
    func seen() {
        guard rang else { return }
        rang = false
        onChange?()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if session?.focus == true { Self.run(shortcut: Self.endShortcutKey) }
        session = nil
    }

    private func ring() {
        stop()
        rang = true
        NSSound(named: Self.sound)?.play()
        onChange?()
    }

    private static func run(shortcut key: String) {
        guard let name = UserDefaults.standard.string(forKey: key), !name.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }

    // The user's Shortcuts by name, for the pickers in Settings.
    static func shortcuts() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return names.split(separator: "\n").map(String.init).sorted()
    }

    // "24:59", or "1:04:59" from an hour up; a second that has started still shows.
    static func text(remaining: TimeInterval) -> String {
        let s = max(0, Int(remaining.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
