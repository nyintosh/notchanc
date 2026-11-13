// Menu-bar-height pill for AirPods Active Noise Cancellation, one per selected display.
// Collapsed:  [AirPods icon] [ ---- camera cutout ---- ] [waveform]
// Hovered:    [AirPods icon] NOISE CANCELLATION ON [ -- cutout -- ] Title — Artist [waveform]
// Both text areas have the ANC label's width; a longer track title scrolls.

import Cocoa

let palette: [(name: String, color: NSColor)] = [
    ("Orange", .systemOrange),
    ("Green",  .systemGreen),
    ("Blue",   .systemBlue),
    ("Purple", .systemPurple),
    ("Pink",   .systemPink),
]

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
        let wing = Self.wing
        let side = 48 + tw + 10   // icon, text, gap before the middle
        if hasCutout {
            // Widths, not midX: correct for any cutout size or position.
            middle = screen.width - leftAux.width - rightAux.width
            window = NSRect(x: screen.minX + leftAux.width - side, y: screen.maxY - h, width: 2 * side + middle, height: h)
        } else {
            middle = 0
            window = NSRect(x: screen.midX - side, y: screen.maxY - h, width: 2 * side, height: h)
        }
        collapsed = NSRect(x: side - wing, y: 0, width: 2 * wing + middle, height: h)
        expanded = NSRect(origin: .zero, size: window.size)
        leftText = NSRect(x: 48, y: 0, width: tw, height: h)
        rightText = NSRect(x: window.width - 48 - tw, y: 0, width: tw, height: h)
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
    private var visible = false
    var color: NSColor = .systemOrange
    var hiddenDisplays: Set<String> = []
    var track: Track? {
        didSet { if track != oldValue { pills.forEach { $0.setTrack(track) } } }
    }

    func setVisible(_ on: Bool) {
        visible = on
        on ? show(animated: true) : hide()
    }

    func refresh() { if visible { show(animated: false) } }

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
        pills = NSScreen.screens.filter { !hiddenDisplays.contains($0.uuid) }.map {
            Pill(screen: $0, color: color, track: track, expanded: open.contains($0.uuid))
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
            if p.hitRect.contains(mouse) {
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
    var collapseTimer: Timer?

    var hitRect: NSRect {
        (expanded ? layout.expanded : layout.collapsed)
            .offsetBy(dx: window.frame.minX, dy: window.frame.minY)
            .insetBy(dx: 0, dy: -2)   // the pointer can sit on the screen's top edge
    }

    init(screen: NSScreen, color: NSColor, track: Track?, expanded: Bool) {
        let anc = NSAttributedString(string: "NOISE CANCELLATION ON",
                                     attributes: [.font: Self.font, .foregroundColor: color, .kern: 0.8])
        layout = screen.pillLayout(textWidth: ceil(anc.size().width))
        uuid = screen.uuid
        scale = screen.backingScaleFactor
        self.color = color
        self.expanded = expanded
        let h = layout.window.height

        window = NSWindow(contentRect: layout.window, styleMask: .borderless, backing: .buffered, defer: false)
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

        let pods = NSImageView(frame: NSRect(x: 16, y: iconY, width: 20, height: 18))
        pods.image = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: "AirPods")?
            .withSymbolConfiguration(cfg)
        pods.contentTintColor = color
        pods.imageScaling = .scaleProportionallyUpOrDown
        pods.autoresizingMask = .maxXMargin
        body.addSubview(pods)

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
        fill(leftClip, with: anc)

        body.frame = expanded ? layout.expanded : layout.collapsed
        leftClip.alphaValue = expanded ? 1 : 0
        rightClip.alphaValue = expanded ? 1 : 0
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
    private func fill(_ clip: NSView, with text: NSAttributedString) {
        clip.layer!.sublayers?.forEach { $0.removeFromSuperlayer() }
        clip.layer!.mask = nil
        let tw = ceil(text.size().width)
        let h = clip.bounds.height
        let overflows = tw > clip.bounds.width
        let scrolls = overflows && !reduceMotion
        let gap: CGFloat = 30
        let copies = scrolls ? Int(ceil(clip.bounds.width / (tw + gap))) + 1 : 1
        let strip = CALayer()
        strip.frame = CGRect(x: 0, y: 0, width: (tw + gap) * CGFloat(copies), height: h)
        for i in 0..<copies {
            let t = CATextLayer()
            t.string = text
            t.contentsScale = scale
            t.frame = CGRect(x: (tw + gap) * CGFloat(i), y: (h - 14) / 2, width: tw + 2, height: 14)
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
        guard overflows else { return }
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
        expanded = on
        let target = on ? layout.expanded : layout.collapsed
        if reduceMotion { body.frame = target }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.2 : (on ? 0.32 : 0.42)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            if !reduceMotion { body.animator().frame = target }
            leftClip.animator().alphaValue = on ? 1 : 0
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
