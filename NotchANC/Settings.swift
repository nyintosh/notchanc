// Preferences window: toolbar tabs, each a small SwiftUI form. Everything is stored in
// UserDefaults; AppDelegate applies changes as they land.

import ServiceManagement
import Sparkle
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let updater: SPUUpdater

    init(updater: SPUUpdater) { self.updater = updater }

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(tab("General", "gearshape", GeneralTab(updater: updater)))
            tabs.addTabViewItem(tab("Appearance", "paintpalette", AppearanceTab()))
            tabs.addTabViewItem(tab("About", "info.circle", AboutTab(updater: updater)))
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func tab(_ title: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.padding(24).frame(width: 460))
        host.sizingOptions = .preferredContentSize
        host.title = title   // the window title follows the selected tab
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

private struct GeneralTab: View {
    let updater: SPUUpdater
    @AppStorage("automatic") private var automatic = true
    @AppStorage("hideMenuBarIcon") private var hideIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var autoUpdate: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _autoUpdate = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            LabeledContent("Detection") {
                Toggle("Read the mode from AirPods", isOn: $automatic)
            }
            LabeledContent("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        guard on != (SMAppService.mainApp.status == .enabled) else { return }
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch { NSSound.beep() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            LabeledContent("Menu bar icon") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide menu bar icon", isOn: $hideIcon)
                    Text("Open NotchANC again to show this window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Updates") {
                Toggle("Check automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in updater.automaticallyChecksForUpdates = on }
            }
        }
        .formStyle(.columns)
    }
}

private struct AppearanceTab: View {
    @AppStorage("accentColor") private var accent = 0
    @State private var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenDisplays") ?? [])
    @State private var screens = NSScreen.screens

    var body: some View {
        Form {
            LabeledContent("Accent color") {
                HStack(spacing: 10) {
                    ForEach(palette.indices, id: \.self) { i in
                        Button { accent = i } label: {
                            Circle().fill(Color(nsColor: palette[i].color))
                                .frame(width: 18, height: 18)
                                .overlay { if accent == i { Circle().stroke(.primary, lineWidth: 2).padding(-3) } }
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .help(palette[i].name)
                        .accessibilityLabel(palette[i].name)
                    }
                }
            }
            LabeledContent("Show on") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(screens, id: \.self) { s in
                        Toggle(s.pillLayout().cutoutName.map { "\(s.localizedName) (\($0))" } ?? s.localizedName,
                               isOn: shown(s.uuid))
                    }
                }
            }
        }
        .formStyle(.columns)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }

    // Stores the hidden ones, so newly connected displays show the pill by default.
    private func shown(_ uuid: String) -> Binding<Bool> {
        Binding(get: { !hidden.contains(uuid) }, set: { on in
            if on { hidden.remove(uuid) } else { hidden.insert(uuid) }
            UserDefaults.standard.set(Array(hidden), forKey: "hiddenDisplays")
        })
    }
}

private struct AboutTab: View {
    let updater: SPUUpdater
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("NotchANC").font(.title2.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Link("github.com/nyintosh/notchanc", destination: URL(string: "https://github.com/nyintosh/notchanc")!)
            Button("Check for Updates…") { updater.checkForUpdates() }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}
