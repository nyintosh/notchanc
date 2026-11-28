// The pill around the camera cutout (notch or Dynamic Island), one per selected display, washed in its state's colour:
// AirPods Noise Cancellation on, or Now Playing while it's off.
// Collapsed, the playing app's icon (or the state's, with no track) sits on the left and the visualizer on the right;
// without a cutout the track's text sits between them and the bar hugs it.
// Hovering opens one card: status chips (Noise Cancellation, where sound is going), the Now Playing player when
// there is a track, and tiles of things worth a glance, the quick timer among them. Tabs in the status row turn
// the card into the file shelf or the clipboard history.
// The collapsed pill's icons travel into the card, and the visualizer rides its edge.

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// Swatches offered in Settings; any other colour comes from the colour picker.
let presets: [(name: String, hex: String)] = [
    ("Orange", "#FF9F0A"), ("Yellow", "#FFD60A"), ("Green", "#30D158"), ("Mint", "#63E6E2"), ("Teal", "#40C8E0"),
    ("Blue", "#0A84FF"), ("Indigo", "#5E5CE6"), ("Purple", "#BF5AF2"), ("Pink", "#FF375F"), ("Red", "#FF453A"),
]

// Menu bar icon choices while Noise Cancellation is off; the first is the default.
let menuBarIcons = ["airpodspro", "airpods", "headphones", "beats.headphones", "ear.fill",
                    "moon.fill", "waveform", "music.note", "speaker.wave.2.fill", "sparkles"]

// Each state has its own colour and icon, stored in UserDefaults (registered at launch).
enum PillMode: CaseIterable {
    case anc, media

    var label: String { self == .anc ? "Noise Cancellation" : "Now Playing" }
    var colorKey: String { self == .anc ? "ancColor" : "mediaColor" }
    var iconKey: String { self == .anc ? "ancIcon" : "mediaIcon" }
    var defaults: [String: Any] {
        self == .anc ? [colorKey: "#FF9F0A", iconKey: "moon.fill"] : [colorKey: "#0A84FF", iconKey: "music.note.list"]
    }
    // ANC: quiet, blocked out. Media: something playing.
    var icons: [String] {
        self == .anc
            ? ["moon.fill", "moon.zzz.fill", "waveform.slash", "shield.lefthalf.filled", "ear.badge.waveform",
               "headphones", "airpodspro", "speaker.slash.fill", "bell.slash.fill", "leaf.fill"]
            : ["music.note.list", "music.note", "music.quarternote.3", "play.fill", "play.circle",
               "waveform", "speaker.wave.2.fill", "headphones", "hifispeaker.fill", "radio.fill"]
    }

    var color: NSColor { NSColor(hex: UserDefaults.standard.string(forKey: colorKey) ?? "") ?? .systemOrange }
    var icon: String { UserDefaults.standard.string(forKey: iconKey) ?? "" }
}

extension NSColor {
    convenience init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        let byte = { (x: CGFloat) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

// Where the pill goes on one screen. macOS reports a notch and a Dynamic Island the same way:
// a top safe-area inset plus the unobscured areas left and right of the camera.
struct PillLayout: Equatable {
    static let edge: CGFloat = 16   // from the pill's end to its icon
    static let icon: CGFloat = 20
    static let gap: CGFloat = 12    // between an icon and the text
    static let wing = 2 * edge + icon   // the pill's reach each side of a cutout
    static let maxText: CGFloat = 290
    static let maxBar = 2 * (edge + icon + gap) + maxText   // the widest bar on a display without a cutout
    static let cardWidth: CGFloat = 600   // wide and short: the pill spreads sideways as it opens

    let bar: NSRect    // the collapsed pill at its widest, screen coordinates
    let open: NSRect   // the bar once the pill has opened, screen coordinates
    let middle: CGFloat     // the cutout's width (0 without one)
    let hasCutout: Bool

    init(screen: NSRect, topInset: CGFloat, leftAux: NSRect, rightAux: NSRect, barHeight: CGFloat) {
        hasCutout = topInset > 0 && !leftAux.isEmpty && !rightAux.isEmpty
        let h = hasCutout ? topInset : barHeight
        if hasCutout {
            // Widths, not midX: correct for any cutout size or position.
            middle = screen.width - leftAux.width - rightAux.width
            bar = NSRect(x: screen.minX + leftAux.width - Self.wing, y: screen.maxY - h, width: 2 * Self.wing + middle, height: h)
        } else {
            middle = 0
            bar = NSRect(x: screen.midX - Self.maxBar / 2, y: screen.maxY - h, width: Self.maxBar, height: h)
        }
        let width = max(bar.width, Self.cardWidth)
        open = NSRect(x: bar.midX - width / 2, y: bar.minY, width: width, height: h)
    }

    // Without a cutout the bar hugs what it holds: the icon, the text if any, and the mark on the right if any.
    static func barWidth(text: CGFloat?, trailing: CGFloat?) -> CGFloat {
        edge + icon + (text.map { gap + min($0, maxText) } ?? 0) + (trailing.map { gap + $0 } ?? 0) + edge
    }

    // ponytail: guesses by width since no API names the cutout; Island Macs ship narrower than every notch (~180pt+).
    var cutoutName: String? { hasCutout ? (middle < 150 ? "Dynamic Island" : "notch") : nil }
}

extension NSScreen {
    func pillLayout() -> PillLayout {
        PillLayout(screen: frame, topInset: safeAreaInsets.top,
                   leftAux: auxiliaryTopLeftArea ?? .zero, rightAux: auxiliaryTopRightArea ?? .zero,
                   barHeight: NSStatusBar.system.thickness)
    }

    // Stable across reboots and reconnects, unlike the display ID.
    var uuid: String {
        let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "\(id)" }
        return CFUUIDCreateString(nil, u) as String
    }
}

final class NotchOverlay {
    private var pills: [Pill] = []
    private var monitors: [Any] = []
    private var shown: PillMode?   // what the pills show; outlives `mode` while the pointer holds the player open
    private let tap = AudioTap()
    private let glance = Glance()
    let countdown = Countdown()
    private let shelf = Shelf()
    private let clipboard = Clipboard()

    init() { clipboard.start() }   // copies are gathered whether or not a pill is showing
    var hiddenDisplays: Set<String> = []
    var menu: NSMenu?   // right-click menu, the same one the menu bar icon shows
    var onCommand: ((MediaCommand) -> Void)?
    var onOpen: (() -> Void)?   // clicking the player's icon or title
    var output = Output(name: "", headphones: false) {
        didSet { if output != oldValue { pills.forEach { $0.setOutput(output) } } }
    }
    var listening: ListeningMode? {   // nil while unknown: no headphones, or detection off
        didSet { if listening != oldValue { pills.forEach { $0.setListening(listening) } } }
    }
    var track: Track? {
        didSet {
            if track != oldValue { pills.forEach { $0.setTrack(track) } }
            listen()
        }
    }

    // The visualizer hears the Mac's output only while a pill shows something playing.
    private func listen() { tap.isRunning = shown != nil && track?.playing == true }

    // The tiles' readings are taken only while a pill is open.
    private func watch() {
        glance.isWatching = pills.contains(where: \.expanded)
        if glance.isWatching { countdown.seen() }
    }

    // nil hides the pill. Switching between ANC and media rebuilds it in the new colour.
    var mode: PillMode? { didSet { update() } }

    func refresh() { if let shown { show(shown, animated: false) } }

    // Pausing from the player ends media mode; the pill waits for the pointer to leave, so Play stays in reach.
    private func update() {
        guard mode != shown else { return }
        if let mode {
            show(mode, animated: shown == nil)
        } else if !pills.contains(where: \.expanded) {
            hide()
        }
    }

    private func hide() {
        shown = nil
        listen()
        glance.isWatching = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        let old = pills
        pills = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            old.forEach { $0.window.animator().alphaValue = 0 }
        }, completionHandler: { old.forEach { $0.close() } })
    }

    private func show(_ mode: PillMode, animated: Bool) {
        shown = mode
        listen()
        let open = Set(pills.filter(\.expanded).map(\.uuid))
        pills.forEach { $0.close() }
        pills = NSScreen.screens.filter { !hiddenDisplays.contains($0.uuid) }.map {
            Pill(screen: $0, mode: mode, color: mode.color, track: track, output: output, listening: listening, expanded: open.contains($0.uuid), menu: menu, tap: tap, glance: glance, countdown: countdown, shelf: shelf, clipboard: clipboard,
                 onCommand: { [weak self] in self?.onCommand?($0) }, onOpen: { [weak self] in self?.onOpen?() })
        }
        for p in pills {
            p.window.alphaValue = animated ? 0 : 1
            p.window.orderFrontRegardless()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                pills.forEach { $0.window.animator().alphaValue = 1 }
            }
        }
        if monitors.isEmpty {
            // Mouse monitors need no permission, and the pill keeps ignoring clicks. Drags count too,
            // so a file carried to the pill opens it.
            let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            monitors = [NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in self?.hover() },
                        NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] e in self?.hover(); return e }]
                .compactMap { $0 }
        }
    }

    // A short wait before opening, so a pointer passing over the menu bar doesn't open it; a longer one before closing.
    private func hover() {
        let mouse = NSEvent.mouseLocation
        // A drag in progress whose pasteboard holds files: the pill opens on the shelf, ready for the drop.
        let carryingFiles = NSEvent.pressedMouseButtons & 1 != 0 && UserDefaults.standard.bool(forKey: CardPart.shelf.rawValue)
            && NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        for p in pills {
            let inside = p.hitRect.contains(mouse)
            // Clicks pass through to the menu bar, except while the pointer is on the pill (buttons, right-click menu).
            if p.window.ignoresMouseEvents == inside { p.window.ignoresMouseEvents = !inside }
            if inside {
                p.collapseTimer?.invalidate(); p.collapseTimer = nil
                if !p.expanded, p.openTimer == nil {
                    p.openTimer = .scheduledTimer(withTimeInterval: Pill.openDelay, repeats: false) { [weak self, weak p] _ in
                        p?.openTimer = nil
                        p?.setExpanded(true, tab: carryingFiles ? .shelf : .now)
                        self?.watch()
                    }
                }
            } else {
                p.openTimer?.invalidate(); p.openTimer = nil
                if p.expanded, p.collapseTimer == nil {
                    p.collapseTimer = .scheduledTimer(withTimeInterval: Pill.closeDelay, repeats: false) { [weak self, weak p] _ in
                        p?.collapseTimer = nil
                        p?.setExpanded(false)
                        self?.watch()
                        self?.update()
                    }
                }
            }
        }
    }
}

// What the SwiftUI drawing follows; the AppKit side changes it inside the pill's animations.
// The parts of the card that Settings can turn off, by their UserDefaults key.
enum CardPart: String, CaseIterable {
    case headphones = "tileHeadphones", calendar = "tileCalendar", mac = "tileMac", timer = "tileTimer"
    case shelf = "tabShelf", clipboard = "tabClipboard"
}

// What the open card shows.
private enum CardTab: CaseIterable {
    case now, shelf, clipboard

    var symbol: String {
        switch self {
        case .now: "square.grid.2x2.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        }
    }

    var label: String {
        switch self {
        case .now: "Now"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        }
    }
}

private final class PillState: ObservableObject {
    @Published var track: Track?
    @Published var appIcon: NSImage?   // the player app's icon, shown in place of album art
    @Published var output: Output
    @Published var listening: ListeningMode?
    @Published var expanded: Bool
    @Published var tab = CardTab.now
    @Published var query = ""   // what the shelf or the clipboard is searched for

    init(output: Output, listening: ListeningMode?, expanded: Bool) {
        self.output = output
        self.listening = listening
        self.expanded = expanded
    }
}

private final class Pill {
    static let chips: CGFloat = 40     // the status row at the top of the card
    static let player: CGFloat = 84    // the Now Playing row under it
    static let tilesGap: CGFloat = 10  // above the tiles when no player sits there
    static let tiles = Tiles.height + 12   // the tiles and the room under them
    static let shadow: CGFloat = 40    // room around the open card for its shadow, so the window never cuts it
    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let countdownWidth: CGFloat = 32   // "24:59" on the bar's right
    static let openDelay: TimeInterval = 0.12
    static let closeDelay: TimeInterval = 0.4

    let window: NSWindow
    let uuid: String
    private let layout: PillLayout
    private let mode: PillMode
    private let countdown: Countdown
    private let clipboard: Clipboard
    private let state: PillState
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let onCommand: (MediaCommand) -> Void
    private var reported: Track?   // the player's own word, which an optimistic play/pause gives way to
    var expanded: Bool { state.expanded }
    var openTimer: Timer?
    var collapseTimer: Timer?

    // The card under the bar: the chips, a hairline, the player if there is a track, then the tiles.
    static let tools: CGFloat = 26 + 8  // the search field and the remove button over a tab's content, and the gap under them
    static let shelf = tilesGap + tools + 84 + 14   // the shelf tab: its tools, then one row of files or the drop zone
    static let clipRow: CGFloat = 30    // one copy in the clipboard tab
    static let clipGap: CGFloat = 6
    static let clipRows = 4             // shown before the list scrolls

    // The clipboard tab is as tall as its copies, up to four; empty, it is the shelf's size, for the same kind of box.
    static func clipboard(_ copies: Int) -> CGFloat {
        guard copies > 0 else { return shelf }
        let rows = CGFloat(min(copies, clipRows))
        return tilesGap + tools + rows * clipRow + (rows - 1) * clipGap + 12
    }

    // Under the chips and the hairline, each tab takes only the room its content needs.
    static func card(_ track: Track?, _ tab: CardTab, copies: Int) -> CGFloat {
        switch tab {
        case .now: chips + 1 + (track == nil ? tilesGap : player) + tiles
        case .shelf: chips + 1 + shelf
        case .clipboard: chips + 1 + clipboard(copies)
        }
    }

    // What the bar says on a display without a cutout.
    static func barText(_ mode: PillMode, _ track: Track?) -> String? { track?.text ?? (mode == .anc ? mode.label : nil) }

    // Core Text measures fallback fonts too; NSAttributedString.size() doesn't.
    static func textWidth(_ text: String) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 2
    }

    // A running countdown takes the right end; otherwise a track brings its bars or pause mark, a rung timer its bell.
    static func barWidth(_ layout: PillLayout, _ mode: PillMode, _ track: Track?, counting: Bool, rang: Bool) -> CGFloat {
        guard !layout.hasCutout else { return layout.bar.width }
        let trailing: CGFloat? = counting ? countdownWidth : track != nil || rang ? PillLayout.icon : nil
        return PillLayout.barWidth(text: barText(mode, track).map(textWidth), trailing: trailing)
    }

    // The window reaches below the bar and beyond its sides for the card;
    // the pill is centred in it and fills only what's shown.
    var hitRect: NSRect {
        let w = state.expanded ? layout.open.width : Self.barWidth(layout, mode, state.track, counting: countdown.session != nil, rang: countdown.rang)
        let h = layout.bar.height + (state.expanded ? Self.card(state.track, state.tab, copies: clipboard.all.count) : 0)
        let f = window.frame
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
            .insetBy(dx: 0, dy: -2)   // the pointer can sit on the screen's top edge
    }

    init(screen: NSScreen, mode: PillMode, color: NSColor, track: Track?, output: Output, listening: ListeningMode?, expanded: Bool,
         menu: NSMenu?,
         tap: AudioTap, glance: Glance, countdown: Countdown, shelf: Shelf, clipboard: Clipboard, onCommand: @escaping (MediaCommand) -> Void, onOpen: @escaping () -> Void) {
        layout = screen.pillLayout()
        self.mode = mode
        self.countdown = countdown
        self.clipboard = clipboard
        uuid = screen.uuid
        state = PillState(output: output, listening: listening, expanded: expanded)
        self.onCommand = onCommand
        let below = Self.chips + 1 + Self.player + Self.tiles + Self.shadow
        var frame = layout.open.insetBy(dx: -Self.shadow, dy: 0)
        frame.origin.y -= below
        frame.size.height += below

        // A non-activating panel: clicking the pill never takes focus from the app in front.
        let panel = PillPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true   // only the search field takes the keyboard; buttons never do
        window = panel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        // Without .fullScreenAuxiliary macOS keeps the window out of full-screen spaces. Only cutout
        // screens keep a black band beside the camera in full screen, so only they keep the pill.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if layout.hasCutout { window.collectionBehavior.insert(.fullScreenAuxiliary) }
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.menu = menu
        window.contentView = root

        let view = PillView(layout: layout, mode: mode, color: color,
                            reduceMotion: reduceMotion, state: state, tap: tap, glance: glance, countdown: countdown, shelf: shelf, clipboard: clipboard,
                            onCommand: { [weak self] in self?.send($0) },
                            onOpen: onOpen)
        let host = FirstClickHostingView(rootView: view)
        host.frame = root.bounds
        root.addSubview(host)
        setTrack(track)
    }

    func setTrack(_ track: Track?) {
        reported = track
        if track?.bundle != state.track?.bundle {
            state.appIcon = track?.bundle.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        withAnimation(reduceMotion ? nil : PillView.open) { state.track = track }
    }

    func setOutput(_ output: Output) { state.output = output }

    func setListening(_ mode: ListeningMode?) { state.listening = mode }

    // Every opening starts on the tab asked for; closing keeps the tab, so the card doesn't change as it leaves.
    func setExpanded(_ on: Bool, tab: CardTab = .now) {
        guard on != state.expanded else { return }
        if on {
            state.tab = tab
            state.query = ""
        }
        withAnimation(reduceMotion ? nil : on ? PillView.open : PillView.close) { state.expanded = on }
        // Typing in the search field made the panel key; putting it back in line returns the keyboard to the app in front.
        if !on, window.isKeyWindow {
            window.orderOut(nil)
            window.orderFrontRegardless()
        }
    }

    // Play/pause answers on the press; the player reports within a second, and if it never does, the pill goes back.
    private func send(_ command: MediaCommand) {
        onCommand(command)
        guard command == .togglePlayPause, let track = state.track else { return }
        state.track = track.toggled(at: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.state.track != self.reported else { return }
            self.state.track = self.reported
        }
    }

    func close() {
        openTimer?.invalidate()
        collapseTimer?.invalidate()
        window.orderOut(nil)
    }
}

// A borderless panel refuses the keyboard unless told otherwise; the search field needs it.
private final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// The panel is rarely key, so without this the first click would only be spent on focus.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// Black pill flush with the top of the screen, bottom corners rounded, washed in the state's colour towards its
// lower edge (the top stays black, to meet the cutout). Its icons are one set that travels between
// the collapsed bar and the open card, so both read as one object changing shape.
// Springs with no bounce, so hovering out halfway turns the pill around
// from where it is, and closing is quicker than opening. The icons move on the shape's clock; the text fades in
// a beat later, once the icons have crossed it, and out at once.
private struct PillView: View {
    static let open = Animation.spring(duration: 0.34, bounce: 0)
    static let close = Animation.spring(duration: 0.26, bounce: 0)
    static let reveal = open.delay(0.1)
    static let conceal = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.15)
    static let swap = Animation.spring(duration: 0.35, bounce: 0)     // play and pause trading places
    static let press = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.15)
    static let margin: CGFloat = 20   // the card's side padding

    let layout: PillLayout
    let mode: PillMode
    let color: NSColor
    let reduceMotion: Bool
    @ObservedObject var state: PillState
    let tap: AudioTap
    let glance: Glance
    @ObservedObject var countdown: Countdown
    let shelf: Shelf
    @ObservedObject var clipboard: Clipboard   // its count sets the clipboard tab's height
    let onCommand: (MediaCommand) -> Void
    let onOpen: () -> Void
    @State private var dropping = false   // files are being held over the pill
    @AppStorage(CardPart.headphones.rawValue) private var showsBattery = true
    @AppStorage(CardPart.shelf.rawValue) private var showsShelf = true
    @AppStorage(CardPart.clipboard.rawValue) private var showsClipboard = true
    @Namespace private var space
    @State private var opening = false   // the press on the icon and title, which the travelling icon follows too

    private var open: Bool { state.expanded }
    private var playing: Bool { state.track?.playing == true }
    private var idle: Bool { mode == .media && !playing }
    private var tint: Color { Color(nsColor: color) }

    var body: some View {
        let h = layout.bar.height
        let card = Pill.card(state.track, state.tab, copies: clipboard.all.count)
        let width = open ? layout.open.width : Pill.barWidth(layout, mode, state.track, counting: countdown.session != nil, rang: countdown.rang)
        let radius: CGFloat = open ? 24 : min(13, h / 2 - 1)   // a 24pt menu bar can't take 13pt corners
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        ZStack(alignment: .top) {
            // The card keeps its final size and the growing pill uncovers it, so nothing reflows mid-motion.
            shape.fill(.black)
                .frame(width: width, height: h + (open ? card : 0))
                .overlay { LinearGradient(colors: [.clear, tint.opacity(idle ? 0.16 : 0.32)], startPoint: .top, endPoint: .bottom) }
                .overlay(alignment: .bottom) {
                    // The countdown has the visualizer's place, so the sound shows as a glow along the lower edge.
                    if playing, countdown.session != nil, !open, !reduceMotion {
                        Glow(tap: tap, tint: tint, bar: h).frame(width: width)
                    }
                }
                .overlay(alignment: .top) {
                    self.card
                        .frame(width: layout.open.width, height: card)
                        .padding(.top, h)
                        .opacity(open ? 1 : 0)
                        .blur(radius: open ? 0 : 2)
                        .animation(reduceMotion ? nil : open ? Self.reveal : Self.conceal, value: open)
                        .allowsHitTesting(open)
                }
                // The edge fades in with the wash, so no line shows along the top of the screen.
                .overlay {
                    shape.stroke(LinearGradient(colors: [.clear, tint.opacity(idle ? 0.14 : 0.28)], startPoint: .top, endPoint: .bottom),
                                 lineWidth: 1)
                }
                .clipShape(shape)
                .shadow(color: .black.opacity(open ? 0.3 : 0), radius: 14, y: 6)
            bar(width: width, height: h)
            icons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard showsShelf else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { shelf.add([url]) } }
                }
            }
            return true
        }
    }

    // Each icon follows the spot marked for it: in the bar, or in the card once it's open.
    // Collapsed, the app's icon stands for a track and the state's icon shows only without one;
    // open, the state's icon sits in its chip while Noise Cancellation is on.
    private var icons: some View {
        let stateOpacity: Double = open ? (mode == .anc ? 1 : 0) : state.track != nil ? 0 : idle ? 0.45 : 1
        return ZStack {
            if state.track != nil, !open || state.tab == .now {   // the other tabs have no place for it
                art
                    .aspectRatio(1, contentMode: .fit)
                    .matchedGeometryEffect(id: Spot.art, in: space, isSource: false)
                    .scaleEffect(opening ? 0.95 : 1)
                    .animation(reduceMotion ? nil : Self.press, value: opening)
            }
            Image(systemName: mode.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityLabel(mode.label)
                .frame(width: PillLayout.icon, height: 18)
                .opacity(stateOpacity)
                .matchedGeometryEffect(id: Spot.state, in: space, isSource: false)
        }
        .allowsHitTesting(false)
    }

    // The player app's icon; a note on a tile for a player that has none.
    @ViewBuilder private var art: some View {
        if let icon = state.appIcon {
            Image(nsImage: icon).resizable()
        } else {
            GeometryReader { g in
                RoundedRectangle(cornerRadius: g.size.height * 0.23, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: g.size.height * 0.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
            }
        }
    }

    private enum Spot { case art, state }

    private func spot(_ id: Spot, inCard: Bool) -> some View {
        Color.clear.frame(width: PillLayout.icon, height: 18).matchedGeometryEffect(id: id, in: space, isSource: inCard == open)
    }

    // The collapsed bar: the icon on the left, what's playing on the right. Without a cutout the text sits between.
    private func bar(width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                HStack(spacing: PillLayout.gap) {
                    ZStack {
                        spot(.state, inCard: false)
                        spot(.art, inCard: false)
                    }
                    if !layout.hasCutout, let text = Pill.barText(mode, state.track) {
                        Marquee(text: NSAttributedString(string: text, attributes: [.font: Pill.font, .foregroundColor: color]),
                                color: color, reduceMotion: reduceMotion)
                            .frame(width: min(Pill.textWidth(text), PillLayout.maxText), height: height)
                            .opacity(open ? 0 : 1)
                    }
                }
                .padding(.leading, PillLayout.edge)
                .fixedSize()
            }
            .overlay(alignment: .trailing) {
                // The mark stays at the top-right corner and rides the edge out.
                trailing
                    .frame(minWidth: PillLayout.icon, minHeight: 18)
                    .padding(.trailing, PillLayout.edge)
            }
            .clipped()
            .allowsHitTesting(false)
    }

    // The bell once a timer has rung, until the card is opened; the countdown while one runs, playing or not;
    // else bars while something plays, a pause mark while a track waits, or nothing.
    @ViewBuilder private var trailing: some View {
        if countdown.rang {
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityLabel("Time's up")
        } else if let session = countdown.session {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Countdown.text(remaining: session.end.timeIntervalSince(context.date)))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(width: Pill.countdownWidth, alignment: .trailing)
            }
            .accessibilityLabel(session.focus ? "Focus session" : "Timer")
        } else if playing {
            Group {
                if reduceMotion {
                    Image(systemName: "waveform").font(.system(size: 13, weight: .semibold))
                } else {
                    Visualizer(tap: tap)
                }
            }
            .foregroundStyle(tint)
            .accessibilityLabel("Media playing")
        } else if state.track != nil {
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityLabel("Paused")
        }
    }

    // Status chips, a hairline, the player if there is a track, then the tiles.
    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                chip(listeningText, on: mode == .anc) {
                    ZStack {
                        spot(.state, inCard: true)
                        if mode != .anc { chipIcon(PillMode.anc.icon).opacity(0.55) }
                    }
                }
                if !state.output.name.isEmpty {
                    chip(state.output.volume.map { "\(state.output.name) · \($0)%" } ?? state.output.name, on: false) {
                        chipIcon(state.output.headphones ? "headphones" : "speaker.wave.2.fill")
                    } trailing: {
                        if showsBattery, state.output.headphones { HeadphonesBattery(glance: glance) }
                    }
                }
                Spacer(minLength: 0)
                tabs
            }
            .frame(height: Pill.chips)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            switch state.tab {
            case .now:
                if let track = state.track {
                    player(track).frame(height: Pill.player)
                } else {
                    Color.clear.frame(height: Pill.tilesGap)
                }
                Tiles(glance: glance, countdown: countdown, tint: tint, reduceMotion: reduceMotion)
                    .frame(height: Pill.tiles, alignment: .top)
            case .shelf:
                ShelfView(shelf: shelf, query: $state.query, dropping: dropping, tint: tint, reduceMotion: reduceMotion)
                    .frame(height: Pill.shelf)
            case .clipboard:
                ClipboardView(clipboard: clipboard, query: $state.query, tint: tint, reduceMotion: reduceMotion)
                    .frame(height: Pill.clipboard(clipboard.all.count))
            }
        }
        .padding(.horizontal, Self.margin)
    }

    // No tab bar when both extra tabs are turned off.
    @ViewBuilder private var tabs: some View {
        let shown = CardTab.allCases.filter { $0 == .now || ($0 == .shelf ? showsShelf : showsClipboard) }
        if shown.count > 1 {
            tabBar(shown)
        }
    }

    private func tabBar(_ shown: [CardTab]) -> some View {
        HStack(spacing: 2) {
            ForEach(shown, id: \.self) { tab in
                Button {
                    state.query = ""
                    withAnimation(reduceMotion ? nil : Self.open) { state.tab = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.tab == tab ? tint : .white.opacity(0.4))
                        .frame(width: 32, height: 26)
                        .background(state.tab == tab ? tint.opacity(0.2) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(Press(reduceMotion: reduceMotion))
                .accessibilityLabel(tab.label)
            }
        }
    }

    // The headphones' own mode when it is known and isn't Noise Cancellation; otherwise just on or off.
    private var listeningText: String {
        if mode == .anc { return "\(PillMode.anc.label) on" }
        if let label = state.listening?.label, state.listening != .off { return label }
        return "\(PillMode.anc.label) off"
    }

    private func chip(_ text: String, on: Bool, @ViewBuilder icon: () -> some View) -> some View {
        chip(text, on: on, icon: icon) { EmptyView() }
    }

    private func chip(_ text: String, on: Bool, @ViewBuilder icon: () -> some View, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 2) {
            icon()
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(on ? 0.95 : 0.6))
                .lineLimit(1)
            trailing()
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 26)
        .background(on ? tint.opacity(0.2) : Color.white.opacity(0.07), in: Capsule())
    }

    private func chipIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: PillLayout.icon, height: 18)
    }

    // One row: icon; title, artist and progress; previous, play/pause, next.
    private func player(_ track: Track) -> some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    Color.clear
                        .frame(width: 52, height: 52)
                        .matchedGeometryEffect(id: Spot.art, in: space, isSource: open)
                    VStack(alignment: .leading, spacing: 2) {
                        Title(text: track.title, reduceMotion: reduceMotion)
                        if !track.artist.isEmpty {   // a browser tab often names no artist; no empty line then
                            Text(track.artist)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            progress(track, at: context.date)
                        }
                        .id(track.title)   // a new track starts its bar afresh instead of sliding back
                        .frame(height: 10)
                        .padding(.top, 8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Press(reduceMotion: reduceMotion, held: $opening))
            .accessibilityLabel("Show \(track.title)")
            HStack(spacing: 2) {
                control("Previous", .previousTrack) { glyph("backward.fill", size: 14) }
                control(track.playing ? "Pause" : "Play", .togglePlayPause) {
                    ZStack {
                        swapping(glyph("pause.fill", size: 20), shown: track.playing)
                        swapping(glyph("play.fill", size: 20), shown: !track.playing)
                    }
                    .animation(reduceMotion ? nil : Self.swap, value: track.playing)
                }
                control("Next", .nextTrack) { glyph("forward.fill", size: 14) }
            }
        }
    }

    @ViewBuilder private func progress(_ track: Track, at now: Date) -> some View {
        if let duration = track.duration, duration > 0, let position = track.position(at: now) {
            let p = min(max(position, 0), duration)
            HStack(spacing: 8) {
                Text(Self.time(p))
                Capsule().fill(.white.opacity(0.1))
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(.white).frame(width: g.size.width * p / duration) }
                    }
                    .frame(height: 3)
                    .animation(reduceMotion || !track.playing ? nil : .linear(duration: 1), value: p)   // glides between ticks
                Text("-" + Self.time(duration - p))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private static func time(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    private func glyph(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
    }

    // One icon becoming the other: the leaving one shrinks far and blurs as the new one grows in its place.
    private func swapping(_ icon: some View, shown: Bool) -> some View {
        icon.opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.3).blur(radius: shown ? 0 : 2)
    }

    // 40pt targets, the size a mouse needs, around small glyphs.
    private func control(_ name: String, _ command: MediaCommand, @ViewBuilder label: () -> some View) -> some View {
        Button { onCommand(command) } label: {
            label().frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(Press(reduceMotion: reduceMotion))
        .accessibilityLabel(name)
    }
}

// The headphones' battery, at the end of the output chip while sound goes to them. Only this view redraws with it.
private struct HeadphonesBattery: View {
    @ObservedObject var glance: Glance

    var body: some View {
        if let headphones = glance.headphones, let level = headphones.level {
            HStack(spacing: 3) {
                Text("·")
                Image(systemName: Self.symbol(level))
                Text("\(level)%")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
            .padding(.leading, 2)
            .help(headphones.charger.map { "\(headphones.name), case \($0)%" } ?? headphones.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Headphones battery \(level) percent")
        }
    }

    // The battery glyph nearest the level, in quarters.
    static func symbol(_ level: Int) -> String {
        "battery.\(min(max((level + 12) / 25 * 25, 0), 100))percent"
    }
}

// A dashed box that says what an empty tab is for; it lights up while files are held over the pill.
private struct EmptySlot: View {
    let symbol: String
    let title: String
    let detail: String
    var lit = false
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(lit ? tint : .white.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((lit ? tint.opacity(0.12) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(lit ? tint : Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

// Over a tab's content: a search field, and one button that empties the tab. The button is always there,
// dimmed while there is nothing to remove.
private struct TabTools: View {
    let prompt: String
    @Binding var query: String
    let remove: String
    let nothingToSearch: Bool
    let nothingToRemove: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(Press(reduceMotion: reduceMotion))
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(.white.opacity(0.08), in: Capsule())
            .disabled(nothingToSearch)
            Button {
                withAnimation(reduceMotion ? nil : PillView.open, action)
            } label: {
                Text(remove)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(Press(reduceMotion: reduceMotion))
            .disabled(nothingToRemove)
            .opacity(nothingToRemove ? 0.4 : 1)
        }
        .environment(\.colorScheme, .dark)   // the pill is always dark, whatever the system wears
    }
}

// What a tab says when a search finds nothing in it.
private func noMatches(_ query: String) -> some View {
    Text("Nothing matches “\(query)”")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// The shelf tab: its tools, then the parked files in a row. Click one to open it, drag it out to use it,
// the cross to take it off.
private struct ShelfView: View {
    @ObservedObject var shelf: Shelf
    @Binding var query: String
    let dropping: Bool
    let tint: Color
    let reduceMotion: Bool

    private var found: [URL] {
        query.isEmpty ? shelf.files : shelf.files.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TabTools(prompt: "Search files", query: $query, remove: "Remove all", nothingToSearch: shelf.files.isEmpty,
                     nothingToRemove: shelf.files.isEmpty, reduceMotion: reduceMotion) { shelf.removeAll() }
            if shelf.files.isEmpty {
                EmptySlot(symbol: "tray.and.arrow.down", title: "Drop files here",
                          detail: "They stay where they are. Drag one out to use it.", lit: dropping, tint: tint)
            } else if found.isEmpty {
                noMatches(query)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(found, id: \.self) { file in
                            Button { NSWorkspace.shared.open(file) } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 44, height: 44)
                                    Text(file.lastPathComponent)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.horizontal, 6)
                                .frame(width: 92, height: 84)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(Press(reduceMotion: reduceMotion))
                            .accessibilityLabel("Open \(file.lastPathComponent)")
                            .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }
                            .overlay(alignment: .topTrailing) {
                                Button { shelf.remove(file) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(Press(reduceMotion: reduceMotion))
                                .accessibilityLabel("Remove \(file.lastPathComponent) from the shelf")
                            }
                            .help(file.path)
                        }
                    }
                }
            }
        }
        .padding(.top, Pill.tilesGap)
        .padding(.bottom, 14)
    }
}

// The clipboard tab: its tools, then the pinned copies and what was copied lately, newest first, each marked by
// what it is. Click one to copy it again; its pin keeps it. Clear all leaves the pinned ones.
private struct ClipboardView: View {
    @ObservedObject var clipboard: Clipboard
    @Binding var query: String
    let tint: Color
    let reduceMotion: Bool
    @State private var copied: String?   // the row just clicked, ticked for a moment

    private var found: [String] {
        query.isEmpty ? clipboard.all : clipboard.all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TabTools(prompt: "Search copies", query: $query, remove: "Clear all", nothingToSearch: clipboard.all.isEmpty,
                     nothingToRemove: clipboard.items.isEmpty, reduceMotion: reduceMotion) { clipboard.clear() }
            if clipboard.all.isEmpty {
                EmptySlot(symbol: "doc.on.clipboard", title: "Nothing copied yet",
                          detail: "What you copy shows up here. Click one to copy it again.", tint: tint)
            } else if found.isEmpty {
                noMatches(query)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Pill.clipGap) {
                        ForEach(found, id: \.self) { text in row(text) }
                    }
                }
            }
        }
        .padding(.top, Pill.tilesGap)
        .padding(.bottom, clipboard.all.isEmpty ? 14 : 12)
    }

    private func row(_ text: String) -> some View {
        let isPinned = clipboard.pinned.contains(text)
        return HStack(spacing: 0) {
            Button { copy(text) } label: {
                HStack(spacing: 8) {
                    mark(Clipboard.kind(of: text)).frame(width: 18)
                    // One line of it: the first that has anything on it.
                    Text(text.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .padding(.leading, 10)
                .frame(height: Pill.clipRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(Press(reduceMotion: reduceMotion))
            .accessibilityLabel("Copy \(text)")
            Button {
                withAnimation(reduceMotion ? nil : PillView.open) { clipboard.togglePin(text) }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isPinned ? tint : .white.opacity(0.4))
                    .frame(width: 28, height: Pill.clipRow)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Press(reduceMotion: reduceMotion))
            .accessibilityLabel(isPinned ? "Unpin" : "Pin")
            Image(systemName: copied == text ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(copied == text ? tint : .white.opacity(0.4))
                .frame(width: 24)
                .padding(.trailing, 6)
                .accessibilityHidden(true)
        }
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func copy(_ text: String) {
        clipboard.copy(text)
        copied = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == text { copied = nil } }
    }

    // A link, a colour shown as itself, or plain text.
    @ViewBuilder private func mark(_ kind: Clipboard.Kind) -> some View {
        switch kind {
        case .link:
            Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
        case .color(let color):
            Circle().fill(Color(nsColor: color)).frame(width: 12, height: 12).overlay { Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
        case .text:
            Image(systemName: "text.alignleft").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

// The card's last row: one small tile per thing worth a glance. Only this view redraws as readings change.
private struct Tiles: View {
    static let height: CGFloat = 64
    static let spacing: CGFloat = 8
    static let width = (PillLayout.cardWidth - 2 * PillView.margin - 3 * spacing) / 4   // room for four in a row

    @ObservedObject var glance: Glance
    @ObservedObject var countdown: Countdown
    let tint: Color
    let reduceMotion: Bool
    @AppStorage(CardPart.calendar.rawValue) private var showsCalendar = true
    @AppStorage(CardPart.mac.rawValue) private var showsMac = true
    @AppStorage(CardPart.timer.rawValue) private var showsTimer = true
    @AppStorage(Countdown.presetKeys[0]) private var first = Countdown.presetDefaults[0]
    @AppStorage(Countdown.presetKeys[1]) private var second = Countdown.presetDefaults[1]
    @AppStorage(Countdown.presetKeys[2]) private var third = Countdown.presetDefaults[2]

    // The row is four tiles wide: the event, the Mac's two, the timer.
    var body: some View {
        HStack(spacing: Self.spacing) {
            if showsCalendar { calendar }
            if showsMac { mac }
            if showsTimer { timer }
            Spacer(minLength: 0)
        }
    }

    // How busy the Mac is, one ring each: processor, graphics, memory, disk.
    private var mac: some View {
        HStack(spacing: 6) {
            ring("CPU", "Processor", glance.mac.processor)
            if let graphics = glance.mac.graphics { ring("GPU", "Graphics", graphics) }
            if let memory = glance.mac.memory { ring("MEM", "Memory", memory) }
            if let disk = glance.mac.disk { ring("SSD", "Disk", disk) }
        }
        .padding(.horizontal, 10)
        .frame(width: 2 * Self.width + Self.spacing, height: Self.height)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // The ring fills clockwise from the top; the number and a short label sit inside it.
    private func ring(_ short: String, _ name: String, _ percent: Int) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(percent)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    + Text("%").font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(short).font(.system(size: 6.5, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 46, height: 46)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(percent) percent")
    }

    // The next event; before that, a button to let the app read the calendar. Hidden once access is refused.
    @ViewBuilder private var calendar: some View {
        switch glance.calendar {
        case .fullAccess:
            if let event = glance.event {
                TimelineView(.everyMinute) { context in
                    tile("calendar", "Next", event.title, event.when(at: context.date))
                }
            } else {
                tile("calendar", "Next", "Nothing", "in the next day")
            }
        case .notDetermined:
            box {
                caption("calendar", "Next")
                Button("Show events") { glance.askForCalendar() }
                    .buttonStyle(Press(reduceMotion: reduceMotion))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.white.opacity(0.1), in: Capsule())
                    .padding(.top, 5)
            }
        default:
            EmptyView()
        }
    }

    // Minutes to start a timer and the moon to start a focus session; while one runs, its time and a way out.
    @ViewBuilder private var timer: some View {
        if let session = countdown.session {
            box {
                caption(session.focus ? "moon.stars.fill" : "timer", session.focus ? "Focus" : "Timer")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    value(Countdown.text(remaining: session.end.timeIntervalSince(context.date)))
                }
                Button("Cancel") { countdown.cancel() }
                    .buttonStyle(Press(reduceMotion: reduceMotion))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
        } else {
            box {
                caption("timer", "Timer")
                HStack(spacing: 3) {
                    ForEach(Array([first, second, third].enumerated()), id: \.offset) { _, minutes in
                        start("\(minutes) minute timer") { countdown.start(minutes: minutes, focus: false) } label: {
                            Text("\(minutes)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                    }
                    start("Focus session") { countdown.startFocus() } label: {
                        Image(systemName: "moon.stars.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    }
                }
                .padding(.top, 5)
            }
        }
    }

    private func start(_ name: String, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 22)
                .background(.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(Press(reduceMotion: reduceMotion))
        .accessibilityLabel(name)
    }

    private func tile(_ symbol: String, _ name: String, _ value: String, _ detail: String?) -> some View {
        box {
            caption(symbol, name)
            self.value(value)
            if let detail {
                Text(detail).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ symbol: String, _ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(.white).lineLimit(1)
    }

    private func box(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3, content: content)
            .padding(10)
            .frame(width: Self.width, height: Self.height, alignment: .topLeading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// The visualizer as light: one smooth wave along the pill's lower edge, low notes on the left, rising with the
// sound and fading upwards. Only this view redraws as it moves.
private struct Glow: View {
    @ObservedObject var tap: AudioTap
    let tint: Color
    let bar: CGFloat   // the pill's height: the wave is sized to it, so a thin menu bar pill isn't flooded

    var body: some View {
        Wave(levels: tap.levels.map { CGFloat($0) })
            .fill(LinearGradient(colors: [tint.opacity(0), tint.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            .frame(height: bar * 0.5)
            .blur(radius: bar * 0.05)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// A curve through one height per band, flat at each so it reads as a wave, falling to nothing at both ends.
private struct Wave: Shape {
    let levels: [CGFloat]   // 0…1, left to right

    func path(in rect: CGRect) -> Path {
        let heights = [0] + levels + [0]
        let step = rect.width / CGFloat(heights.count - 1)
        let points = heights.enumerated().map { CGPoint(x: rect.minX + CGFloat($0.offset) * step, y: rect.maxY - $0.element * rect.height) }
        var path = Path()
        path.move(to: points[0])
        for (from, to) in zip(points, points.dropFirst()) {
            let middle = (from.x + to.x) / 2
            path.addCurve(to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
        }
        path.closeSubpath()
        return path
    }
}

// Bars that follow what's playing, low notes on the left: thin, rounded,
// growing both ways from the middle. Only this view redraws as they move.
private struct Visualizer: View {
    @ObservedObject var tap: AudioTap

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tap.levels.indices, id: \.self) { i in
                Capsule().frame(width: 2, height: 3 + CGFloat(tap.levels[i]) * 11)
            }
        }
        .animation(.linear(duration: 0.05), value: tap.levels)   // eases between the ~47 readings a second
        .frame(height: 14)
    }
}

// Buttons give a little while held.
private struct Press: ButtonStyle {
    let reduceMotion: Bool
    var held: Binding<Bool>?   // tells parts drawn outside the button, like the travelling icon, to press with it
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(reduceMotion ? nil : PillView.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { held?.wrappedValue = $1 }
    }
}

// The player's title, drawn by SwiftUI so the entrance blur reaches it. Static when it fits,
// otherwise it scrolls like the bar's marquee: 32 points a second, a dot between repeats, faded edges.
private struct Title: View {
    let text: String
    let reduceMotion: Bool
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    private let gap: CGFloat = 30

    var body: some View {
        let scrolls = textWidth > boxWidth && !reduceMotion
        Color.clear
            .frame(height: 18)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: !scrolls)) { context in
                    let cycle = textWidth + gap
                    let shift = scrolls ? CGFloat(context.date.timeIntervalSinceReferenceDate * 32).truncatingRemainder(dividingBy: cycle) : 0
                    HStack(spacing: 0) {
                        label
                        if scrolls {
                            Circle().fill(.white).frame(width: 4, height: 4).frame(width: gap)
                            label
                        }
                    }
                    .offset(x: -shift)
                }
            }
            .mask {
                if scrolls {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                           .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                } else {
                    Color.black
                }
            }
            .background(alignment: .leading) {
                label.hidden().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
    }

    private var label: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
    }
}

// Static text when it fits, otherwise a marquee with faded edges.
private struct Marquee: NSViewRepresentable {
    let text: NSAttributedString
    let color: NSColor
    let reduceMotion: Bool

    func makeNSView(context: Context) -> MarqueeView { MarqueeView() }

    func updateNSView(_ view: MarqueeView, context: Context) {
        view.update(text: text, color: color, reduceMotion: reduceMotion)
    }
}

private final class MarqueeView: NSView {
    private var text = NSAttributedString()
    private var color = NSColor.white
    private var reduceMotion = false
    private var filled: (NSAttributedString, CGSize)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer!.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(text: NSAttributedString, color: NSColor, reduceMotion: Bool) {
        self.text = text
        self.color = color
        self.reduceMotion = reduceMotion
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard filled?.0 != text || filled?.1 != bounds.size else { return }
        filled = (text, bounds.size)
        fill()
    }

    private func fill() {
        layer!.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer!.mask = nil
        let font = text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Pill.font : Pill.font
        // Core Text measures fallback fonts too (Myanmar needs ~24pt, Latin 13pt); NSAttributedString.size()
        // doesn't. Every string sits on the baseline that centres Latin text, so both sides line up.
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let tw = ceil(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let h = bounds.height
        let baseline = (h - font.ascender + font.descender) / 2 - font.descender
        let overflows = tw > bounds.width
        let scrolls = overflows && !reduceMotion
        let gap: CGFloat = 30
        let copies = scrolls ? Int(ceil(bounds.width / (tw + gap))) + 1 : 1
        let strip = CALayer()
        strip.frame = CGRect(x: overflows || scrolls ? 0 : (bounds.width - tw) / 2, y: 0,
                             width: (tw + gap) * CGFloat(copies), height: h)
        for i in 0..<copies {
            let t = CATextLayer()
            t.string = text
            t.contentsScale = window?.backingScaleFactor ?? 2
            t.frame = CGRect(x: (tw + gap) * CGFloat(i), y: baseline - descent, width: tw + 2, height: ceil(ascent + descent))
            strip.addSublayer(t)
            if scrolls {   // separator dot in the gap between repeats
                let d = CALayer()
                d.backgroundColor = color.cgColor
                d.cornerRadius = 2
                d.frame = CGRect(x: (tw + gap) * CGFloat(i) + tw + gap / 2 - 2, y: (h - 5) / 2, width: 4, height: 4)
                strip.addSublayer(d)
            }
        }
        layer!.addSublayer(strip)
        guard overflows || scrolls else { return }
        let fade = CAGradientLayer()
        fade.frame = bounds
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.08, 0.92, 1]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer!.mask = fade
        guard scrolls else { return }
        let scroll = CABasicAnimation(keyPath: "transform.translation.x")
        scroll.fromValue = 0
        scroll.toValue = -(tw + gap)
        scroll.duration = Double(tw + gap) / 32.0
        scroll.repeatCount = .infinity
        scroll.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(scroll, forKey: "marquee")
    }
}

