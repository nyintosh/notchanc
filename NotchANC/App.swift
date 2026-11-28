import Cocoa
import Sparkle

// When the Now Playing pill shows while Noise Cancellation is off.
enum MediaVisibility: String, CaseIterable {
    case never, headphones, anyOutput, always

    static let key = "mediaVisibility"

    var title: String {
        switch self {
        case .never: "Never"
        case .headphones: "With headphones"
        case .anyOutput: "With any output"
        case .always: "Always"
        }
    }

    func shows(playing: Bool, toHeadphones: Bool) -> Bool {
        switch self {
        case .never: false
        case .headphones: playing && toHeadphones
        case .anyOutput: playing
        case .always: true
        }
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = NotchOverlay()
    private let monitor = AirPodsMonitor()
    private let nowPlaying = NowPlaying()
    private let output = AudioOutput()
    private let hotkeys = Hotkeys()
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
    private var visibility = MediaVisibility.headphones
    private var iconHidden = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        defaults.register(defaults: PillMode.allCases.reduce(["automatic": true, MediaVisibility.key: MediaVisibility.headphones.rawValue,
                                                             Countdown.focusMinutesKey: Countdown.focusLengths[0], "menuBarIcon": menuBarIcons[0]]) {
            $0.merging($1.defaults) { a, _ in a }
        }
        .merging(Dictionary(uniqueKeysWithValues: zip(Countdown.presetKeys, Countdown.presetDefaults))) { a, _ in a }
        .merging(Dictionary(uniqueKeysWithValues: CardPart.allCases.map { ($0.rawValue, true) })) { a, _ in a }
        .merging(Dictionary(uniqueKeysWithValues: Shortcut.defaults.map { (Shortcut.key(for: $0.key), $0.value.stored) })) { a, _ in a })
        // 1.0.0–1.0.3 kept one accent colour as an index into five swatches.
        if let i = defaults.object(forKey: "accentColor") as? Int {
            defaults.set(["#FF9F0A", "#30D158", "#0A84FF", "#BF5AF2", "#FF375F"][min(max(i, 0), 4)], forKey: PillMode.anc.colorKey)
            defaults.removeObject(forKey: "accentColor")
        }
        // 1.0.4–1.0.6 kept an on/off switch for the Now Playing pill.
        if let on = defaults.object(forKey: "showMedia") as? Bool {
            if !on { defaults.set(MediaVisibility.never.rawValue, forKey: MediaVisibility.key) }
            defaults.removeObject(forKey: "showMedia")
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
        monitor.onChange = { [weak self] mode in
            guard let self, self.autoItem.state == .on else { return }
            self.overlay.listening = mode
            let on = mode == .noiseCancellation
            if on != self.ancOn { self.set(on) }
        }
        nowPlaying.onChange = { [weak self] track in
            self?.track = track
            self?.overlay.track = track
            self?.updatePill()
        }
        overlay.countdown.onChange = { [weak self] in self?.updatePill() }
        overlay.onCommand = { [weak self] in self?.nowPlaying.send($0) }
        overlay.onSummon = { [weak self] in self?.updatePill() }
        hotkeys.onPress = { [weak self] in self?.overlay.summon($0) }
        overlay.onOpen = { [weak self] in if let track = self?.overlay.track { self?.nowPlaying.open(track) } }
        nowPlaying.start()   // also shows the pill for media while ANC is off
        output.onChange = { [weak self] in
            guard let self else { return }
            self.overlay.output = self.output.current
            self.updatePill()
        }
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
                overlay.listening = nil
                statusLine.title = "Automatic detection off"
            }
        }

        let look = PillMode.allCases.flatMap { [defaults.string(forKey: $0.colorKey) ?? "", defaults.string(forKey: $0.iconKey) ?? ""] }
            + [defaults.string(forKey: "menuBarIcon") ?? ""]
        let hidden = Set(defaults.stringArray(forKey: "hiddenDisplays") ?? [])
        if look != self.look || hidden != overlay.hiddenDisplays {
            self.look = look
            overlay.hiddenDisplays = hidden
            overlay.refresh()
            setStatusIcon(on: ancOn)
        }

        for part in Shortcut.parts {
            hotkeys.set(Shortcut(stored: defaults.string(forKey: Shortcut.key(for: part)) ?? ""), for: part)
        }

        let visibility = defaults.string(forKey: MediaVisibility.key).flatMap(MediaVisibility.init) ?? .headphones
        if visibility != self.visibility {
            self.visibility = visibility
            updatePill()
        }
    }

    private func setStatusIcon(on: Bool) {
        let img = NSImage(systemSymbolName: on ? PillMode.anc.icon : defaults.string(forKey: "menuBarIcon") ?? menuBarIcons[0],
                          accessibilityDescription: "NotchANC")
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

    // ANC wins; otherwise Settings decide when the Now Playing pill shows; a timer or a shortcut's card keeps it up.
    private func updatePill() {
        hideMedia?.cancel()
        let mode: PillMode? = ancOn ? .anc
            : (visibility.shows(playing: track?.playing == true, toHeadphones: output.toHeadphones) || overlay.countdown.isActive || overlay.summoned ? .media : nil)
        guard mode == nil, overlay.mode == .media else { overlay.mode = mode; return }
        // Players report "paused" for a moment between tracks; don't flash the pill.
        let work = DispatchWorkItem { [weak self] in self?.overlay.mode = nil }
        hideMedia = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
