import Cocoa
import Sparkle

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = NotchOverlay()
    private let monitor = AirPodsMonitor()
    private let nowPlaying = NowPlaying()
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var settings = SettingsWindow(updater: updater.updater)
    private let defaults = UserDefaults.standard
    private var item: NSStatusItem!
    private var toggle: NSMenuItem!
    private var autoItem: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var ancOn = false
    private var track: Track?
    private var hideMedia: DispatchWorkItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        defaults.register(defaults: ["automatic": true])

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon(on: false)

        let menu = NSMenu()
        toggle = NSMenuItem(title: "Noise Cancellation On", action: #selector(flip), keyEquivalent: "n")
        toggle.target = self
        menu.addItem(toggle)

        autoItem = NSMenuItem(title: "Automatic (read from AirPods)", action: #selector(toggleAuto), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)
        statusLine = NSMenuItem(title: "Automatic detection off", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)
        menu.addItem(NSMenuItem(title: "Quit NotchANC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        overlay.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.overlay.refresh()
        }
        // The Settings window and the menu both write UserDefaults; this applies whatever changed.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        }

        monitor.onStatus = { [weak self] text in DispatchQueue.main.async { self?.statusLine.title = text } }
        monitor.onChange = { [weak self] on in
            guard let self, self.autoItem.state == .on, on != self.ancOn else { return }
            self.set(on)
        }
        nowPlaying.onChange = { [weak self] track in
            self?.track = track
            self?.overlay.track = track
            self?.updatePill()
        }
        nowPlaying.start()   // also shows the pill for media while ANC is off
        apply()

        // External hook for scripts/detectors: post "notchanc.set" with object "on" or "off".
        DistributedNotificationCenter.default().addObserver(forName: .init("notchanc.set"),
                                                            object: nil, queue: .main) { [weak self] note in
            self?.set((note.object as? String) == "on")
        }
    }

    // Opening the app again (Spotlight, Finder) is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    // Idempotent: UserDefaults notifies for every write, including Sparkle's own bookkeeping.
    private func apply() {
        item.isVisible = !defaults.bool(forKey: "hideMenuBarIcon")

        let automatic = defaults.bool(forKey: "automatic")
        if (autoItem.state == .on) != automatic {
            autoItem.state = automatic ? .on : .off
            if automatic {
                monitor.start()
            } else {
                monitor.stop()
                statusLine.title = "Automatic detection off"
            }
        }

        let color = palette[min(max(defaults.integer(forKey: "accentColor"), 0), palette.count - 1)].color
        let hidden = Set(defaults.stringArray(forKey: "hiddenDisplays") ?? [])
        if color != overlay.color || hidden != overlay.hiddenDisplays {
            overlay.color = color
            overlay.hiddenDisplays = hidden
            overlay.refresh()
        }
    }

    private func setStatusIcon(on: Bool) {
        let img = NSImage(systemSymbolName: on ? "moon.fill" : "airpodspro", accessibilityDescription: "Noise Cancellation")
        img?.isTemplate = true
        item.button?.image = img
    }

    @objc private func flip() { set(!ancOn) }

    @objc private func toggleAuto() { defaults.set(autoItem.state != .on, forKey: "automatic") }

    @objc private func showSettings() { settings.show() }

    private func set(_ on: Bool) {
        ancOn = on
        toggle.state = on ? .on : .off
        setStatusIcon(on: on)
        updatePill()
    }

    // ANC wins; otherwise the pill shows (in blue) while media plays.
    private func updatePill() {
        hideMedia?.cancel()
        let mode: PillMode? = ancOn ? .anc : (track?.playing == true ? .media : nil)
        guard mode == nil, overlay.mode == .media else { overlay.mode = mode; return }
        // Players report "paused" for a moment between tracks; don't flash the pill.
        let work = DispatchWorkItem { [weak self] in self?.overlay.mode = nil }
        hideMedia = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
