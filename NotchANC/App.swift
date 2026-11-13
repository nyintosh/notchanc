import Cocoa
import ServiceManagement
import Sparkle

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let overlay = NotchOverlay()
    private let monitor = AirPodsMonitor()
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private let defaults = UserDefaults.standard
    private var item: NSStatusItem!
    private var toggle: NSMenuItem!
    private var autoItem: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var colorItems: [NSMenuItem] = []
    private let screensMenu = NSMenu()
    private var ancOn = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        defaults.register(defaults: ["automatic": true])
        let colorIndex = min(max(defaults.integer(forKey: "accentColor"), 0), palette.count - 1)
        overlay.color = palette[colorIndex].color
        overlay.hiddenDisplays = Set(defaults.stringArray(forKey: "hiddenDisplays") ?? [])

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon(on: false)

        let menu = NSMenu()
        toggle = NSMenuItem(title: "Noise Cancellation On", action: #selector(flip), keyEquivalent: "n")
        toggle.target = self
        menu.addItem(toggle)

        autoItem = NSMenuItem(title: "Automatic (read from AirPods)", action: #selector(toggleAuto), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)
        statusLine = NSMenuItem(title: "AirPods: starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        screensMenu.delegate = self
        let screensParent = NSMenuItem(title: "Show On", action: nil, keyEquivalent: "")
        screensParent.submenu = screensMenu
        menu.addItem(screensParent)

        let colorMenu = NSMenu()
        for (i, p) in palette.enumerated() {
            let mi = NSMenuItem(title: p.name, action: #selector(pickColor(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            mi.state = i == colorIndex ? .on : .off
            colorMenu.addItem(mi)
            colorItems.append(mi)
        }
        let colorParent = NSMenuItem(title: "Accent Color", action: nil, keyEquivalent: "")
        colorParent.submenu = colorMenu
        menu.addItem(colorParent)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About NotchANC", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)
        menu.addItem(NSMenuItem(title: "Quit NotchANC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.overlay.refresh()
        }

        monitor.onStatus = { [weak self] text in DispatchQueue.main.async { self?.statusLine.title = text } }
        monitor.onChange = { [weak self] on in
            guard let self, self.autoItem.state == .on, on != self.ancOn else { return }
            self.set(on)
        }
        setAutomatic(defaults.bool(forKey: "automatic"))

        // External hook for scripts/detectors: post "notchanc.set" with object "on" or "off".
        DistributedNotificationCenter.default().addObserver(forName: .init("notchanc.set"),
                                                            object: nil, queue: .main) { [weak self] note in
            self?.set((note.object as? String) == "on")
        }
    }

    // Rebuilt on open, so it always lists the displays connected right now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for screen in NSScreen.screens {
            let name = screen.pillLayout.cutoutName.map { "\(screen.localizedName) (\($0))" } ?? screen.localizedName
            let mi = NSMenuItem(title: name, action: #selector(toggleScreen(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = screen.uuid
            mi.state = overlay.hiddenDisplays.contains(screen.uuid) ? .off : .on
            menu.addItem(mi)
        }
    }

    private func setStatusIcon(on: Bool) {
        let img = NSImage(systemSymbolName: on ? "waveform" : "airpodspro", accessibilityDescription: "Noise Cancellation")
        img?.isTemplate = true
        item.button?.image = img
    }

    @objc private func flip() { set(!ancOn) }

    @objc private func toggleAuto() { setAutomatic(autoItem.state != .on) }

    private func setAutomatic(_ on: Bool) {
        defaults.set(on, forKey: "automatic")
        autoItem.state = on ? .on : .off
        if on {
            monitor.start()
        } else {
            monitor.stop()
            statusLine.title = "Automatic detection off"
        }
    }

    @objc private func toggleScreen(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        if overlay.hiddenDisplays.remove(uuid) == nil { overlay.hiddenDisplays.insert(uuid) }
        defaults.set(Array(overlay.hiddenDisplays), forKey: "hiddenDisplays")
        overlay.refresh()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "accentColor")
        overlay.color = palette[sender.tag].color
        colorItems.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        overlay.refresh()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func set(_ on: Bool) {
        ancOn = on
        toggle.state = on ? .on : .off
        setStatusIcon(on: on)
        overlay.setVisible(on)
    }
}
