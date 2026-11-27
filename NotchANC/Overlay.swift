// The pill around the camera cutout (notch or Dynamic Island), one per selected display, in its state's colour:
// AirPods Noise Cancellation on, or media playing into headphones while it's off.
// Collapsed, the state's icon and the visualizer ride its ends; without a cutout the track scrolls between them.
// Hovering opens it. With a track it opens into the Now Playing player and the collapsed pill's parts travel into it:
// the state icon becomes the badge on the player app's icon, which grows out of it, and the visualizer rides the edge.
// Without a track it widens to show the labels beside the cutout.

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

    var label: String { self == .anc ? "NOISE CANCELLATION ON" : "NOW PLAYING" }
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
// The window always has the expanded size; only the pill inside it grows and shrinks.
struct PillLayout: Equatable {
    static let wing: CGFloat = 52

    let window: NSRect      // screen coordinates
    let collapsed: NSRect   // pill, window coordinates
    let expanded: NSRect    // pill, window coordinates
    let leftText: NSRect    // window coordinates
    let rightText: NSRect   // window coordinates
    let middle: CGFloat     // the cutout's width (0 without one)
    let hasCutout: Bool

    init(screen: NSRect, topInset: CGFloat, leftAux: NSRect, rightAux: NSRect, barHeight: CGFloat, textWidth tw: CGFloat) {
        hasCutout = topInset > 0 && !leftAux.isEmpty && !rightAux.isEmpty
        let h = hasCutout ? topInset : barHeight
        if hasCutout {
            // Widths, not midX: correct for any cutout size or position.
            middle = screen.width - leftAux.width - rightAux.width
            let side = 48 + tw + 10   // icon, text, gap before the cutout
            window = NSRect(x: screen.minX + leftAux.width - side, y: screen.maxY - h, width: 2 * side + middle, height: h)
            collapsed = NSRect(x: side - Self.wing, y: 0, width: 2 * Self.wing + middle, height: h)
            leftText = NSRect(x: 48, y: 0, width: tw, height: h)
            rightText = NSRect(x: window.width - 48 - tw, y: 0, width: tw, height: h)
        } else {
            middle = 0
            window = NSRect(x: screen.midX - 193, y: screen.maxY - h, width: 386, height: h)
            collapsed = NSRect(origin: .zero, size: window.size)
            leftText = NSRect(x: 48, y: 0, width: 290, height: h)
            rightText = leftText   // same place: hovering swaps one for the other
        }
        expanded = NSRect(origin: .zero, size: window.size)
    }

    // ponytail: guesses by width since no API names the cutout; Island Macs ship narrower than every notch (~180pt+).
    var cutoutName: String? { hasCutout ? (middle < 150 ? "Dynamic Island" : "notch") : nil }
}

extension NSScreen {
    func pillLayout(textWidth: CGFloat = 0) -> PillLayout {
        PillLayout(screen: frame, topInset: safeAreaInsets.top,
                   leftAux: auxiliaryTopLeftArea ?? .zero, rightAux: auxiliaryTopRightArea ?? .zero,
                   barHeight: NSStatusBar.system.thickness, textWidth: textWidth)
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
            Pill(screen: $0, mode: mode, color: mode.color, track: track, expanded: open.contains($0.uuid), menu: menu, tap: tap,
                 onCommand: { [weak self] in self?.onCommand?($0) })
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
    @Published var appIcon: NSImage?   // the player app's icon, shown where Alcove shows album art
    @Published var expanded: Bool

    init(expanded: Bool) { self.expanded = expanded }
}

private final class Pill {
    static let player: CGFloat = 92         // the Now Playing panel that opens below the bar
    static let playerWidth: CGFloat = 600   // wide and short: the pill spreads sideways from the notch as it opens
    static let shadow: CGFloat = 40         // room around the open player for its shadow, so the window never cuts it
    static let below = player + shadow      // the window's reach below the bar
    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let openDelay: TimeInterval = 0.12
    static let closeDelay: TimeInterval = 0.4

    let window: NSWindow
    let uuid: String
    private let layout: PillLayout
    private let state: PillState
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let onCommand: (MediaCommand) -> Void
    private var reported: Track?   // the player's own word, which an optimistic play/pause gives way to
    var expanded: Bool { state.expanded }
    var openTimer: Timer?
    var collapseTimer: Timer?

    // The window reaches below the bar and, if the player needs it, beyond the bar's sides;
    // the pill is centred in it and fills only what's shown.
    var hitRect: NSRect {
        let w = !state.expanded ? layout.collapsed.width : state.track == nil ? layout.expanded.width : Self.openWidth(layout)
        let h = layout.window.height + (state.expanded && state.track != nil ? Self.player : 0)
        let f = window.frame
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
            .insetBy(dx: 0, dy: -2)   // the pointer can sit on the screen's top edge
    }

    // With a track the pill opens to the player; without one, to the full width of both labels.
    static func openWidth(_ layout: PillLayout) -> CGFloat { max(layout.expanded.width, playerWidth) }

    init(screen: NSScreen, mode: PillMode, color: NSColor, track: Track?, expanded: Bool, menu: NSMenu?, tap: AudioTap,
         onCommand: @escaping (MediaCommand) -> Void) {
        // Sized by the ANC label in both modes, so switching modes never changes the pill's size.
        let width = NSAttributedString(string: PillMode.anc.label, attributes: [.font: Self.font, .kern: 0.8]).size().width
        layout = screen.pillLayout(textWidth: ceil(width))
        uuid = screen.uuid
        state = PillState(expanded: expanded)
        self.onCommand = onCommand
        var frame = layout.window
        frame.origin.y -= Self.below
        frame.size.height += Self.below
        frame = frame.insetBy(dx: -max(0, Self.openWidth(layout) - frame.width) / 2 - Self.shadow, dy: 0)

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

        let view = PillView(layout: layout, mode: mode, color: color, fixed: !layout.hasCutout && mode == .media,
                            reduceMotion: reduceMotion, state: state, tap: tap, onCommand: { [weak self] in self?.send($0) })
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

// Black pill flush with the top of the screen, bottom corners rounded. Its icons are one set that travels between
// the collapsed bar and the open player, so both read as one object changing shape.
// Motion follows the charles-ux-animation skill: springs with no bounce, so hovering out halfway turns the pill around
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
    let fixed: Bool   // media on a display without a cutout: the bar shows the track instead of the label
    let reduceMotion: Bool
    @ObservedObject var state: PillState
    let tap: AudioTap
    let onCommand: (MediaCommand) -> Void
    @Namespace private var space

    private var showsPlayer: Bool { state.expanded && state.track != nil }

    var body: some View {
        let h = layout.window.height
        let width = !state.expanded ? layout.collapsed.width : showsPlayer ? Pill.openWidth(layout) : layout.expanded.width
        let radius: CGFloat = showsPlayer ? 24 : min(13, h / 2 - 1)   // a 24pt menu bar can't take 13pt corners
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        ZStack(alignment: .top) {
            // The player keeps its final size and the growing pill uncovers it, so nothing reflows mid-motion.
            shape.fill(.black)
                .frame(width: width, height: h + (showsPlayer ? Pill.player : 0))
                .overlay(alignment: .top) {
                    if let track = state.track {
                        player(track)
                            .frame(width: Pill.openWidth(layout), height: Pill.player)
                            .padding(.top, h)
                            .opacity(showsPlayer ? 1 : 0)
                            .blur(radius: showsPlayer ? 0 : 2)
                            .animation(reduceMotion ? nil : showsPlayer ? Self.reveal : Self.conceal, value: showsPlayer)
                            .allowsHitTesting(showsPlayer)
                    }
                }
                .overlay { shape.stroke(.white.opacity(0.06), lineWidth: 1) }
                .clipShape(shape)
                .shadow(color: .black.opacity(showsPlayer ? 0.3 : 0), radius: 14, y: 6)
            bar(width: width, height: h)
            icons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Each icon follows the spot marked for it: in the bar, or in the player once it's open.
    private var icons: some View {
        ZStack {
            if state.track != nil {
                Image(nsImage: state.appIcon ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .matchedGeometryEffect(id: Spot.art, in: space, isSource: false)
                    .animation(reduceMotion ? nil : showsPlayer ? Self.open : Self.conceal) { $0.opacity(showsPlayer ? 1 : 0) }
            }
            Image(systemName: mode.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: color))
                .accessibilityLabel(mode.label.capitalized)
                .frame(width: 20, height: 18)
                .background { Circle().fill(.black).frame(width: 26, height: 26).opacity(showsPlayer ? 1 : 0) }
                .matchedGeometryEffect(id: Spot.state, in: space, isSource: false)
        }
        .allowsHitTesting(false)
    }

    private enum Spot { case art, state }

    private func spot(_ id: Spot, inPlayer: Bool) -> some View {
        Color.clear.frame(width: 20, height: 18).matchedGeometryEffect(id: id, in: space, isSource: inPlayer == showsPlayer)
    }

    // Beside a cutout the labels show only when the pill opens without a track; with one, the player takes over.
    // Without a cutout the text sits between the icons until the player opens.
    private func bar(width: CGFloat, height: CGFloat) -> some View {
        let label = NSAttributedString(string: mode.label, attributes: [.font: Pill.font, .foregroundColor: color, .kern: 0.8])
        let track = state.track.map { NSAttributedString(string: $0.text, attributes: [.font: Pill.font, .foregroundColor: color]) }
            ?? NSAttributedString(string: "Not playing", attributes: [.font: Pill.font, .foregroundColor: color.withAlphaComponent(0.5)])
        return Color.clear
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                HStack(spacing: 12) {
                    ZStack {
                        spot(.state, inPlayer: false)
                        spot(.art, inPlayer: false)   // the app icon grows out of the state icon
                    }
                    if layout.hasCutout {
                        Marquee(text: label, color: color, reduceMotion: reduceMotion)
                            .frame(width: layout.leftText.width, height: height)
                            .opacity(state.expanded && state.track == nil ? 1 : 0)
                    } else {
                        Marquee(text: fixed ? track : label, color: color, always: !fixed, reduceMotion: reduceMotion)
                            .frame(width: layout.leftText.width, height: height)
                            .opacity(showsPlayer ? 0 : 1)
                    }
                }
                .padding(.leading, 16)
                .fixedSize()
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 12) {
                    if layout.hasCutout {
                        Marquee(text: track, color: color, reduceMotion: reduceMotion)
                            .frame(width: layout.rightText.width, height: height)
                            .opacity(state.expanded && state.track == nil ? 1 : 0)
                    }
                    // The visualizer stays at the top-right corner and rides the edge out, as on the Dynamic Island.
                    Group {
                        if reduceMotion {
                            Image(systemName: "waveform").font(.system(size: 13, weight: .semibold))
                        } else {
                            Visualizer(tap: tap)
                        }
                    }
                    .foregroundStyle(Color(nsColor: color))
                    .accessibilityLabel("Media playing")
                    .frame(width: 20, height: 18)
                }
                .padding(.trailing, 16)
                .fixedSize()
            }
            .clipped()
            .allowsHitTesting(false)
    }

    // One row, as wide as the opened pill: icon; title, artist and progress; previous, play/pause, next.
    private func player(_ track: Track) -> some View {
        HStack(spacing: 14) {
            Color.clear
                .frame(width: 60, height: 60)
                .matchedGeometryEffect(id: Spot.art, in: space, isSource: showsPlayer)
                .overlay(alignment: .bottomTrailing) {   // the state icon as a badge on the corner
                    spot(.state, inPlayer: true)
                        .alignmentGuide(.trailing) { $0[.trailing] - 7 }
                        .alignmentGuide(.bottom) { $0[.bottom] - 6 }
                }
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
            .allowsHitTesting(false)
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
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
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

// Bars that follow what's playing, low notes on the left, drawn like the Dynamic Island's: thin, rounded,
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(reduceMotion ? nil : PillView.press, value: configuration.isPressed)
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

// Static text when it fits, otherwise a marquee with faded edges; `always` scrolls even when it fits.
private struct Marquee: NSViewRepresentable {
    let text: NSAttributedString
    let color: NSColor
    var always = false
    let reduceMotion: Bool

    func makeNSView(context: Context) -> MarqueeView { MarqueeView() }

    func updateNSView(_ view: MarqueeView, context: Context) {
        view.update(text: text, color: color, always: always, reduceMotion: reduceMotion)
    }
}

private final class MarqueeView: NSView {
    private var text = NSAttributedString()
    private var color = NSColor.white
    private var always = false
    private var reduceMotion = false
    private var filled: (NSAttributedString, CGSize)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer!.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(text: NSAttributedString, color: NSColor, always: Bool, reduceMotion: Bool) {
        self.text = text
        self.color = color
        self.always = always
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
        let scrolls = (overflows || always) && !reduceMotion
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

