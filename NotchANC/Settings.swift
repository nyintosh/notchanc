// Settings window: a sidebar of areas and, beside it, the chosen area's grouped rows. Everything is stored in
// UserDefaults; AppDelegate and the pill apply changes as they land.

import ServiceManagement
import Sparkle
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let updater: SPUUpdater

    init(updater: SPUUpdater) { self.updater = updater }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(updater: updater)))
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.title = "NotchANC Settings"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Pane: String, CaseIterable {
    case general, pill, card, focus, about

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .pill: "capsule.tophalf.filled"
        case .card: "rectangle.grid.1x2"
        case .focus: "moon.stars"
        case .about: "info.circle"
        }
    }
}

private struct SettingsView: View {
    let updater: SPUUpdater
    @State private var pane = Pane.general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, id: \.self, selection: Binding(get: { pane }, set: { pane = $0 ?? pane })) {
                Label($0.title, systemImage: $0.symbol)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane(updater: updater)
                case .pill: PillPane()
                case .card: CardPane()
                case .focus: FocusPane()
                case .about: AboutPane(updater: updater)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(width: 720, height: 470)
    }
}

private struct GeneralPane: View {
    let updater: SPUUpdater
    @AppStorage("automatic") private var automatic = true
    @AppStorage("hideMenuBarIcon") private var hideIcon = false
    @AppStorage("menuBarIcon") private var menuBarIcon = menuBarIcons[0]
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var autoUpdate: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _autoUpdate = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Read the mode from AirPods", isOn: $automatic)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        guard on != (SMAppService.mainApp.status == .enabled) else { return }
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch { NSSound.beep() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in updater.automaticallyChecksForUpdates = on }
            }
            Section("Menu bar icon") {
                VStack(alignment: .leading, spacing: 6) {
                    IconPicker(selection: $menuBarIcon, icons: menuBarIcons, tint: .primary)
                        .disabled(hideIcon)
                    Text("While Noise Cancellation is on, it shows your Noise Cancellation icon.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $hideIcon) {
                    Text("Hide menu bar icon")
                    Text("Open NotchANC again to show this window.")
                }
            }
        }
    }
}

private struct PillPane: View {
    @AppStorage(MediaVisibility.key) private var visibility = MediaVisibility.headphones
    @State private var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenDisplays") ?? [])
    @State private var screens = NSScreen.screens

    var body: some View {
        Form {
            Section(PillMode.anc.label) {
                StyleEditor(mode: .anc)
            }
            Section(PillMode.media.label) {
                Picker("Show", selection: $visibility) {
                    ForEach(MediaVisibility.allCases, id: \.self) { Text($0.title) }
                }
                StyleEditor(mode: .media).disabled(visibility == .never)
            }
            Section("Show on") {
                ForEach(screens, id: \.self) { s in
                    Toggle(s.pillLayout().cutoutName.map { "\(s.localizedName) (\($0))" } ?? s.localizedName,
                           isOn: shown(s.uuid))
                }
            }
        }
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

// What the open card holds: each tile and each extra tab can be turned off.
private struct CardPane: View {
    @AppStorage(CardPart.headphones.rawValue) private var headphones = true
    @AppStorage(CardPart.calendar.rawValue) private var calendar = true
    @AppStorage(CardPart.mac.rawValue) private var mac = true
    @AppStorage(CardPart.timer.rawValue) private var timer = true
    @AppStorage(CardPart.shelf.rawValue) private var shelf = true
    @AppStorage(CardPart.clipboard.rawValue) private var clipboard = true

    var body: some View {
        Form {
            Section("Tiles") {
                Toggle("Headphones battery", isOn: $headphones)
                Toggle("Next calendar event", isOn: $calendar)
                Toggle("Mac battery and processor", isOn: $mac)
                Toggle("Timer and focus", isOn: $timer)
            }
            Section("Tabs") {
                Toggle("File shelf", isOn: $shelf)
                Toggle(isOn: $clipboard) {
                    Text("Clipboard history")
                    Text("Kept in memory only, and never anything a password manager marks as secret.")
                }
            }
        }
    }
}

private struct FocusPane: View {
    @AppStorage(Countdown.presetKeys[0]) private var first = Countdown.presetDefaults[0]
    @AppStorage(Countdown.presetKeys[1]) private var second = Countdown.presetDefaults[1]
    @AppStorage(Countdown.presetKeys[2]) private var third = Countdown.presetDefaults[2]
    @AppStorage(Countdown.focusMinutesKey) private var focusMinutes = Countdown.focusLengths[0]
    @AppStorage(Countdown.startShortcutKey) private var startShortcut = ""
    @AppStorage(Countdown.endShortcutKey) private var endShortcut = ""
    @State private var shortcuts: [String] = []

    var body: some View {
        Form {
            Section("Timer") {
                Stepper("First: \(first) minutes", value: $first, in: Countdown.presetRange)
                Stepper("Second: \(second) minutes", value: $second, in: Countdown.presetRange)
                Stepper("Third: \(third) minutes", value: $third, in: Countdown.presetRange)
            }
            Section {
                Picker("Length", selection: $focusMinutes) {
                    ForEach(Countdown.focusLengths, id: \.self) { Text("\($0) minutes") }
                }
                shortcutPicker("When it starts, run", selection: $startShortcut)
                shortcutPicker("When it ends, run", selection: $endShortcut)
            } header: {
                Text("Focus session")
            } footer: {
                Text("macOS lets no app switch Focus, so pick Shortcuts that turn yours on and off.")
            }
        }
        .task { shortcuts = await Task.detached { Countdown.shortcuts() }.value }
    }

    // A chosen Shortcut that was since deleted stays listed, so the menu still shows what is stored.
    private func shortcutPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Nothing").tag("")
            ForEach(shortcuts.contains(selection.wrappedValue) || selection.wrappedValue.isEmpty
                    ? shortcuts : shortcuts + [selection.wrappedValue], id: \.self) { Text($0).tag($0) }
        }
    }
}

// Colour (swatches or any colour from the picker) and icon for one pill state.
private struct StyleEditor: View {
    let mode: PillMode
    @AppStorage private var color: String
    @AppStorage private var icon: String

    init(mode: PillMode) {
        self.mode = mode
        _color = AppStorage(wrappedValue: mode.defaults[mode.colorKey] as! String, mode.colorKey)
        _icon = AppStorage(wrappedValue: mode.defaults[mode.iconKey] as! String, mode.iconKey)
    }

    private var tint: Color { Color(nsColor: NSColor(hex: color) ?? .systemOrange) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.hex) { preset in
                    Button { color = preset.hex } label: {
                        Circle().fill(Color(nsColor: NSColor(hex: preset.hex)!))
                            .frame(width: 18, height: 18)
                            .overlay { if color == preset.hex { Circle().stroke(.primary, lineWidth: 2).padding(-3) } }
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help(preset.name)
                    .accessibilityLabel(preset.name)
                }
                ColorPicker("Custom color", selection: Binding(get: { tint }, set: { color = NSColor($0).hex }), supportsOpacity: false)
                    .labelsHidden()
                    .help("Any color")
            }
            IconPicker(selection: $icon, icons: mode.icons, tint: tint)
        }
    }
}

// A row of SF Symbols; the chosen one gets a subtle background.
private struct IconPicker: View {
    @Binding var selection: String
    let icons: [String]
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(icons, id: \.self) { name in
                Button { selection = name } label: {
                    Image(systemName: name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 24)
                        .background(selection == name ? Color.primary.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(name)
                .accessibilityLabel(name)
            }
        }
    }
}

private struct AboutPane: View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
