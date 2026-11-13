// Menu-bar-height pill for AirPods Active Noise Cancellation, one per selected display.
// Beside a camera cutout (notch or Dynamic Island):
//   Collapsed:  [moon] [ ---- cutout ---- ] [waveform]
//   Hovered:    [moon] NOISE CANCELLATION ON [ -- cutout -- ] Title — Artist [waveform]
//   Both text areas have the ANC label's width; a longer track title scrolls.
// Without a cutout the pill keeps its full size and hovering swaps the text in place:
//   [moon] NOISE CANCELLATION ON • NOISE CANC… [waveform]  →  [moon] Title — Artist [waveform]
// With ANC off but media playing, the pill shows in blue with a music note list: beside a cutout as above
// with "NOW PLAYING" as the label; elsewhere the current track shows directly, hovered or not.

import Cocoa

// Swatches offered in Settings; any other colour comes from the colour picker.
let presets: [(name: String, hex: String)] = [
    ("Orange", "#FF9F0A"), ("Yellow", "#FFD60A"), ("Green", "#30D158"), ("Mint", "#63E6E2"), ("Teal", "#40C8E0"),
    ("Blue", "#0A84FF"), ("Indigo", "#5E5CE6"), ("Purple", "#BF5AF2"), ("Pink", "#FF375F"), ("Red", "#FF453A"),
]

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
    var hiddenDisplays: Set<String> = []
    var menu: NSMenu?   // right-click menu, the same one the menu bar icon shows
    var track: Track? {
        didSet { if track != oldValue { pills.forEach { $0.setTrack(track) } } }
    }

    // nil hides the pill. Switching between ANC and media rebuilds it in the new colour.
    var mode: PillMode? {
        didSet {
            guard mode != oldValue else { return }
            mode == nil ? hide() : show(animated: oldValue == nil)
        }
    }

    func refresh() { if mode != nil { show(animated: false) } }

    private func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        let old = pills
        pills = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            old.forEach { $0.window.animator().alphaValue = 0 }
        }, completionHandler: { old.forEach { $0.close() } })
    }

    private func show(animated: Bool) {
        let open = Set(pills.filter(\.expanded).map(\.uuid))
        pills.forEach { $0.close() }
        guard let mode else { return }
        pills = NSScreen.screens.filter { !hiddenDisplays.contains($0.uuid) }.map {
            Pill(screen: $0, mode: mode, color: mode.color, track: track, expanded: open.contains($0.uuid), menu: menu)
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

    private func hover() {
        let mouse = NSEvent.mouseLocation
        for p in pills {
            let inside = p.hitRect.contains(mouse)
            // Clicks pass through to the menu bar, except while the pointer is on the pill (right-click menu).
            if p.window.ignoresMouseEvents == inside { p.window.ignoresMouseEvents = !inside }
            if inside {
                p.collapseTimer?.invalidate(); p.collapseTimer = nil
                if !p.expanded { p.setExpanded(true) }
            } else if p.expanded, p.collapseTimer == nil {
                p.collapseTimer = .scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak p] _ in
                    p?.collapseTimer = nil
                    p?.setExpanded(false)
                }
            }
        }
    }
}

private final class Pill {
    let window: NSWindow
    let uuid: String
    private let layout: PillLayout
    private let color: NSColor
    private let scale: CGFloat
    private let body: NSView
    private let leftClip: NSView
    private let rightClip: NSView
    private let wave: NSImageView
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private(set) var expanded: Bool
    private let fixed: Bool   // media on a display without a cutout: the track always shows, hover changes nothing
    var collapseTimer: Timer?

    var hitRect: NSRect {
        (expanded ? layout.expanded : layout.collapsed)
            .offsetBy(dx: window.frame.minX, dy: window.frame.minY)
            .insetBy(dx: 0, dy: -2)   // the pointer can sit on the screen's top edge
    }

    init(screen: NSScreen, mode: PillMode, color: NSColor, track: Track?, expanded: Bool, menu: NSMenu?) {
        // Sized by the ANC label in both modes, so switching modes never changes the pill's size.
        let width = NSAttributedString(string: PillMode.anc.label, attributes: [.font: Self.font, .kern: 0.8]).size().width
        let label = NSAttributedString(string: mode.label,
                                       attributes: [.font: Self.font, .foregroundColor: color, .kern: 0.8])
        layout = screen.pillLayout(textWidth: ceil(width))
        uuid = screen.uuid
        scale = screen.backingScaleFactor
        self.color = color
        self.expanded = expanded
        fixed = !layout.hasCutout && mode == .media
        let h = layout.window.height

        // A non-activating panel: clicking the pill never takes focus from the app in front.
        let panel = NSPanel(contentRect: layout.window, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        let root = NSView(frame: NSRect(origin: .zero, size: layout.window.size))
        root.menu = menu
        window.contentView = root

        // Black pill flush with the cutout, bottom corners rounded. Built expanded; everything on
        // the left rides the left edge and everything on the right rides the right edge, so the
        // icons and text slide outward as it opens.
        body = NSView(frame: layout.expanded)
        body.wantsLayer = true
        body.layer!.backgroundColor = NSColor.black.cgColor
        body.layer!.cornerRadius = 11
        body.layer!.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        body.layer!.masksToBounds = true
        root.addSubview(body)

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let iconY = (h - 18) / 2

        let icon = NSImageView(frame: NSRect(x: 16, y: iconY, width: 20, height: 18))
        icon.image = NSImage(systemSymbolName: mode.icon, accessibilityDescription: mode.label.capitalized)?
            .withSymbolConfiguration(cfg)
        icon.contentTintColor = color
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.autoresizingMask = .maxXMargin
        body.addSubview(icon)

        wave = NSImageView(frame: NSRect(x: layout.expanded.width - 36, y: iconY, width: 20, height: 18))
        wave.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Media playing")?
            .withSymbolConfiguration(cfg)
        wave.contentTintColor = color
        wave.imageScaling = .scaleProportionallyUpOrDown
        wave.autoresizingMask = .minXMargin
        body.addSubview(wave)

        leftClip = Self.clip(layout.leftText, .maxXMargin)
        rightClip = Self.clip(layout.rightText, .minXMargin)
        body.addSubview(leftClip)
        body.addSubview(rightClip)
        if !fixed { fill(leftClip, with: label, alwaysScroll: !layout.hasCutout) }

        body.frame = expanded ? layout.expanded : layout.collapsed
        leftClip.alphaValue = !fixed && layout.hasCutout == expanded ? 1 : 0
        rightClip.alphaValue = fixed || expanded ? 1 : 0
        setTrack(track)
    }

    private static func clip(_ frame: NSRect, _ mask: NSView.AutoresizingMask) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.layer!.masksToBounds = true
        v.autoresizingMask = mask
        return v
    }

    func setTrack(_ track: Track?) {
        let text = track.map { NSAttributedString(string: $0.text, attributes: [.font: Self.font, .foregroundColor: color]) }
            ?? NSAttributedString(string: "Not playing", attributes: [.font: Self.font, .foregroundColor: color.withAlphaComponent(0.5)])
        fill(rightClip, with: text)
        setPlaying(track?.playing == true)
    }

    // Static text when it fits, otherwise a marquee with faded edges.
    private func fill(_ clip: NSView, with text: NSAttributedString, alwaysScroll: Bool = false) {
        clip.layer!.sublayers?.forEach { $0.removeFromSuperlayer() }
        clip.layer!.mask = nil
        // Core Text measures fallback fonts too (Myanmar needs ~24pt, Latin 13pt); NSAttributedString.size()
        // doesn't. Every string sits on the baseline that centres Latin text, so both sides line up.
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let tw = ceil(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let h = clip.bounds.height
        let baseline = (h - Self.font.ascender + Self.font.descender) / 2 - Self.font.descender
        let overflows = tw > clip.bounds.width
        let scrolls = (overflows || alwaysScroll) && !reduceMotion
        let gap: CGFloat = 30
        let copies = scrolls ? Int(ceil(clip.bounds.width / (tw + gap))) + 1 : 1
        let strip = CALayer()
        strip.frame = CGRect(x: overflows || scrolls ? 0 : (clip.bounds.width - tw) / 2, y: 0,
                             width: (tw + gap) * CGFloat(copies), height: h)
        for i in 0..<copies {
            let t = CATextLayer()
            t.string = text
            t.contentsScale = scale
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
        clip.layer!.addSublayer(strip)
        guard overflows || scrolls else { return }
        let fade = CAGradientLayer()
        fade.frame = clip.bounds
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.08, 0.92, 1]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        clip.layer!.mask = fade
        guard scrolls else { return }
        let scroll = CABasicAnimation(keyPath: "transform.translation.x")
        scroll.fromValue = 0
        scroll.toValue = -(tw + gap)
        scroll.duration = Double(tw + gap) / 32.0
        scroll.repeatCount = .infinity
        scroll.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(scroll, forKey: "marquee")
    }

    // Matches the reference recording: a quick ease-out, no bounce; the text fades with the motion.
    func setExpanded(_ on: Bool) {
        guard !fixed else { return }
        expanded = on
        let target = on ? layout.expanded : layout.collapsed
        if reduceMotion { body.frame = target }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.2 : (on ? 0.32 : 0.42)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            if !reduceMotion { body.animator().frame = target }
            leftClip.animator().alphaValue = layout.hasCutout == on ? 1 : 0
            rightClip.animator().alphaValue = on ? 1 : 0
        }
    }

    // The waveform moves only while media plays.
    private func setPlaying(_ on: Bool) {
        wave.removeAllSymbolEffects()
        if on && !reduceMotion { wave.addSymbolEffect(.variableColor.iterative.reversing, options: .repeating) }
    }

    func close() {
        collapseTimer?.invalidate()
        window.orderOut(nil)
    }
}
