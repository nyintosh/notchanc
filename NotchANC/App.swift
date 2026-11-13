import Cocoa
import Sparkle

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = NotchOverlay()
    private let monitor = AirPodsMonitor()
    private let nowPlaying = NowPlaying()
    private let output = AudioOutput()
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
    private var look: [String] = []   // every state's colour and icon, to notice changes
    private var showMedia = true
    private var iconHidden = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        defaults.register(defaults: PillMode.allCases.reduce(["automatic": true, "showMedia": true]) { $0.merging($1.defaults) { a, _ in a } })
        // 1.0.0–1.0.3 kept one accent colour as an index into five swatches.
        if let i = defaults.object(forKey: "accentColor") as? Int {
            defaults.set(["#FF9F0A", "#30D158", "#0A84FF", "#BF5AF2", "#FF375F"][min(max(i, 0), 4)], forKey: PillMode.anc.colorKey)
            defaults.removeObject(forKey: "accentColor")
        }

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
        output.onChange = { [weak self] in self?.updatePill() }
        output.start()
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
        // Changing isVisible makes AppKit write UserDefaults, which re-enters apply() before the change lands.
        // Compare against our own copy, set first, so the re-entrant call does nothing.
        let hide = defaults.bool(forKey: "hideMenuBarIcon")
        if hide != iconHidden {
            iconHidden = hide
            item.isVisible = !hide
        }

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

        let look = PillMode.allCases.flatMap { [defaults.string(forKey: $0.colorKey) ?? "", defaults.string(forKey: $0.iconKey) ?? ""] }
        let hidden = Set(defaults.stringArray(forKey: "hiddenDisplays") ?? [])
        if look != self.look || hidden != overlay.hiddenDisplays {
            self.look = look
            overlay.hiddenDisplays = hidden
            overlay.refresh()
            setStatusIcon(on: ancOn)
        }

        if showMedia != defaults.bool(forKey: "showMedia") {
            showMedia.toggle()
            updatePill()
        }
    }

    private func setStatusIcon(on: Bool) {
        let img = NSImage(systemSymbolName: on ? PillMode.anc.icon : "airpodspro", accessibilityDescription: "Noise Cancellation")
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

    // ANC wins; otherwise the pill shows while media plays into headphones (unless turned off in Settings).
    private func updatePill() {
        hideMedia?.cancel()
        let mode: PillMode? = ancOn ? .anc : (showMedia && track?.playing == true && output.toHeadphones ? .media : nil)
        guard mode == nil, overlay.mode == .media else { overlay.mode = mode; return }
        // Players report "paused" for a moment between tracks; don't flash the pill.
        let work = DispatchWorkItem { [weak self] in self?.overlay.mode = nil }
        hideMedia = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
