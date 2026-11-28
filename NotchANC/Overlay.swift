// The pill around the camera cutout (notch or Dynamic Island), one per selected display, washed in its state's colour:
// AirPods Noise Cancellation on, or Now Playing while it's off.
// Collapsed, the playing app's icon (or the state's, with no track) sits on the left and the visualizer on the right;
// without a cutout the track's text sits between them and the bar hugs it.
// Hovering opens one card: status chips (Noise Cancellation, where sound is going) above the Now Playing player.
// The collapsed pill's icons travel into the card, and the visualizer rides its edge.

import Cocoa
import SwiftUI

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
    static func barWidth(text: CGFloat?, trailing: Bool) -> CGFloat {
        edge + icon + (text.map { gap + min($0, maxText) } ?? 0) + (trailing ? gap + icon : 0) + edge
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
    var hiddenDisplays: Set<String> = []
    var menu: NSMenu?   // right-click menu, the same one the menu bar icon shows
    var onCommand: ((MediaCommand) -> Void)?
    var onOpen: (() -> Void)?   // clicking the player's icon or title
    var output = Output(name: "", headphones: false) {
        didSet { if output != oldValue { pills.forEach { $0.setOutput(output) } } }
    }
    var track: Track? {
        didSet {
            if track != oldValue { pills.forEach { $0.setTrack(track) } }
            listen()
        }
    }

    // The visualizer hears the Mac's output only while a pill shows something playing.
    private func listen() { tap.isRunning = shown != nil && track?.playing == true }

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
            Pill(screen: $0, mode: mode, color: mode.color, track: track, output: output, expanded: open.contains($0.uuid), menu: menu, tap: tap,
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
            // Mouse-moved monitors need no permission, and the pill keeps ignoring clicks.
            monitors = [NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.hover() },
                        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in self?.hover(); return e }]
                .compactMap { $0 }
        }
    }

    // A short wait before opening, so a pointer passing over the menu bar doesn't open it; a longer one before closing.
    private func hover() {
        let mouse = NSEvent.mouseLocation
        for p in pills {
            let inside = p.hitRect.contains(mouse)
            // Clicks pass through to the menu bar, except while the pointer is on the pill (buttons, right-click menu).
            if p.window.ignoresMouseEvents == inside { p.window.ignoresMouseEvents = !inside }
            if inside {
                p.collapseTimer?.invalidate(); p.collapseTimer = nil
                if !p.expanded, p.openTimer == nil {
                    p.openTimer = .scheduledTimer(withTimeInterval: Pill.openDelay, repeats: false) { [weak p] _ in
                        p?.openTimer = nil
                        p?.setExpanded(true)
                    }
                }
            } else {
                p.openTimer?.invalidate(); p.openTimer = nil
                if p.expanded, p.collapseTimer == nil {
                    p.collapseTimer = .scheduledTimer(withTimeInterval: Pill.closeDelay, repeats: false) { [weak self, weak p] _ in
                        p?.collapseTimer = nil
                        p?.setExpanded(false)
                        self?.update()
                    }
                }
            }
        }
    }
}

// What the SwiftUI drawing follows; the AppKit side changes it inside the pill's animations.
private final class PillState: ObservableObject {
    @Published var track: Track?
    @Published var appIcon: NSImage?   // the player app's icon, shown in place of album art
    @Published var output: Output
    @Published var expanded: Bool

    init(output: Output, expanded: Bool) {
        self.output = output
        self.expanded = expanded
    }
}

private final class Pill {
    static let chips: CGFloat = 40     // the status row at the top of the card
    static let player: CGFloat = 84    // the Now Playing row under it
    static let empty: CGFloat = 48     // what takes the player's place with no track
    static let shadow: CGFloat = 40    // room around the open card for its shadow, so the window never cuts it
    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let openDelay: TimeInterval = 0.12
    static let closeDelay: TimeInterval = 0.4

    let window: NSWindow
    let uuid: String
    private let layout: PillLayout
    private let mode: PillMode
    private let state: PillState
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let onCommand: (MediaCommand) -> Void
    private var reported: Track?   // the player's own word, which an optimistic play/pause gives way to
    var expanded: Bool { state.expanded }
    var openTimer: Timer?
    var collapseTimer: Timer?

    // The card under the bar: the chips, a hairline, then the player or its stand-in.
    static func card(_ track: Track?) -> CGFloat { chips + 1 + (track == nil ? empty : player) }

    // What the bar says on a display without a cutout.
    static func barText(_ mode: PillMode, _ track: Track?) -> String? { track?.text ?? (mode == .anc ? mode.label : nil) }

    // Core Text measures fallback fonts too; NSAttributedString.size() doesn't.
    static func textWidth(_ text: String) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 2
    }

    static func barWidth(_ layout: PillLayout, _ mode: PillMode, _ track: Track?) -> CGFloat {
        guard !layout.hasCutout else { return layout.bar.width }
        return PillLayout.barWidth(text: barText(mode, track).map(textWidth), trailing: track != nil)
    }

    // The window reaches below the bar and beyond its sides for the card;
    // the pill is centred in it and fills only what's shown.
    var hitRect: NSRect {
        let w = state.expanded ? layout.open.width : Self.barWidth(layout, mode, state.track)
        let h = layout.bar.height + (state.expanded ? Self.card(state.track) : 0)
        let f = window.frame
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
            .insetBy(dx: 0, dy: -2)   // the pointer can sit on the screen's top edge
    }

    init(screen: NSScreen, mode: PillMode, color: NSColor, track: Track?, output: Output, expanded: Bool, menu: NSMenu?,
         tap: AudioTap, onCommand: @escaping (MediaCommand) -> Void, onOpen: @escaping () -> Void) {
        layout = screen.pillLayout()
        self.mode = mode
        uuid = screen.uuid
        state = PillState(output: output, expanded: expanded)
        self.onCommand = onCommand
        let below = Self.chips + 1 + Self.player + Self.shadow
        var frame = layout.open.insetBy(dx: -Self.shadow, dy: 0)
        frame.origin.y -= below
        frame.size.height += below

        // A non-activating panel: clicking the pill never takes focus from the app in front.
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
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
                            reduceMotion: reduceMotion, state: state, tap: tap, onCommand: { [weak self] in self?.send($0) },
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

    func setExpanded(_ on: Bool) {
        guard on != state.expanded else { return }
        withAnimation(reduceMotion ? nil : on ? PillView.open : PillView.close) { state.expanded = on }
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

// The panel never becomes key, so without this the first click would only be spent on focus.
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

    let layout: PillLayout
    let mode: PillMode
    let color: NSColor
    let reduceMotion: Bool
    @ObservedObject var state: PillState
    let tap: AudioTap
    let onCommand: (MediaCommand) -> Void
    let onOpen: () -> Void
    @Namespace private var space
    @State private var opening = false   // the press on the icon and title, which the travelling icon follows too

    private var open: Bool { state.expanded }
    private var playing: Bool { state.track?.playing == true }
    private var idle: Bool { mode == .media && !playing }
    private var tint: Color { Color(nsColor: color) }

    var body: some View {
        let h = layout.bar.height
        let card = Pill.card(state.track)
        let width = open ? layout.open.width : Pill.barWidth(layout, mode, state.track)
        let radius: CGFloat = open ? 24 : min(13, h / 2 - 1)   // a 24pt menu bar can't take 13pt corners
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        ZStack(alignment: .top) {
            // The card keeps its final size and the growing pill uncovers it, so nothing reflows mid-motion.
            shape.fill(.black)
                .frame(width: width, height: h + (open ? card : 0))
                .overlay { LinearGradient(colors: [.clear, tint.opacity(idle ? 0.16 : 0.32)], startPoint: .top, endPoint: .bottom) }
                .overlay(alignment: .top) {
                    self.card
                        .frame(width: layout.open.width, height: card)
                        .padding(.top, h)
                        .opacity(open ? 1 : 0)
                        .blur(radius: open ? 0 : 2)
                        .animation(reduceMotion ? nil : open ? Self.reveal : Self.conceal, value: open)
                        .allowsHitTesting(open)
                }
                .overlay { shape.stroke(tint.opacity(idle ? 0.3 : 0.55), lineWidth: 1) }
                .clipShape(shape)
                .shadow(color: .black.opacity(open ? 0.3 : 0), radius: 14, y: 6)
            bar(width: width, height: h)
            icons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Each icon follows the spot marked for it: in the bar, or in the card once it's open.
    // Collapsed, the app's icon stands for a track and the state's icon shows only without one;
    // open, the state's icon sits in its chip while Noise Cancellation is on.
    private var icons: some View {
        let stateOpacity: Double = open ? (mode == .anc ? 1 : 0) : state.track != nil ? 0 : idle ? 0.45 : 1
        return ZStack {
            if state.track != nil {
                Image(nsImage: state.appIcon ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
                    .frame(width: PillLayout.icon, height: 18)
                    .padding(.trailing, PillLayout.edge)
            }
            .clipped()
            .allowsHitTesting(false)
    }

    // Bars while something plays, a pause mark while it waits, nothing without a track.
    @ViewBuilder private var trailing: some View {
        if playing {
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

    // Status chips, a hairline, then the player or its stand-in.
    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                chip(mode == .anc ? "\(PillMode.anc.label) on" : "\(PillMode.anc.label) off", on: mode == .anc) {
                    ZStack {
                        spot(.state, inCard: true)
                        if mode != .anc { chipIcon(PillMode.anc.icon).opacity(0.55) }
                    }
                }
                if !state.output.name.isEmpty {
                    chip(state.output.name, on: false) {
                        chipIcon(state.output.headphones ? "headphones" : "speaker.wave.2.fill")
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: Pill.chips)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            if let track = state.track {
                player(track).frame(height: Pill.player)
            } else {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Pill.empty)
            }
        }
        .padding(.horizontal, 20)
    }

    private func chip(_ text: String, on: Bool, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 2) {
            icon()
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(on ? 0.95 : 0.6))
                .lineLimit(1)
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
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
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

